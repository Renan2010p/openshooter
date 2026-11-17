extends Node
## LAN networking: ENet server/client and server discovery over UDP broadcast.

signal servers_changed
signal joined
signal join_failed(reason: String)
signal disconnected(reason: String)
signal players_changed

const PORT := 24540
const DISCOVERY_PORT := 24541
## LAN discovery tag. Bumped when versions can no longer play together
## (1.1.0: the Christmas decorations change the map collision), so servers of
## other versions do not show up in the list.
const GAME_TAG := "openshooter-2"
## Only players with exactly this game version may join (see register()).
static var GAME_VERSION: String = ProjectSettings.get_setting("application/config/version", "")

## Current server information: name, mode, private, code, max, bots, minutes.
var server_info := {}
## Match players: id -> {name, shirt, pants, skin, kills, deaths, bot}.
var players := {}
## Servers found on the network: "ip" -> info + "ip" + "seen".
var found := {}

var _peer: ENetMultiplayerPeer
var _send: PacketPeerUDP
var _listen: PacketPeerUDP
var _broadcast_t := 0.0
var _join_code := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): join_failed.emit("Could not connect to the server."); leave())
	multiplayer.server_disconnected.connect(func(): leave(); disconnected.emit("The connection to the server was lost."))


static func code_hash(code: String) -> String:
	return ("openshooter:" + code).sha256_text().substr(0, 16)


func is_online() -> bool:
	return _peer != null


# ------------------------------------------------------------------ server

func host(info: Dictionary) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, int(info.get("max", 12)))
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	server_info = info
	server_info["version"] = GAME_VERSION
	players.clear()
	var me := Config.profile()
	me.merge({"kills": 0, "deaths": 0, "bot": false, "ready": true})
	players[1] = me
	_send = PacketPeerUDP.new()
	_send.set_broadcast_enabled(true)
	return OK


func humans() -> int:
	var n := 0
	for id in players:
		if not players[id].get("bot", false):
			n += 1
	return n


@rpc("any_peer", "reliable")
func register(profile: Dictionary, code: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if server_info.get("private", false) and code != server_info.get("code", ""):
		reason = "Incorrect private code."
	elif str(profile.get("version", "")) != GAME_VERSION:
		# Older clients (1.0) send no version at all.
		reason = "Version mismatch: the server runs OpenShooter %s, you have %s." % [
			GAME_VERSION, str(profile.get("version", "1.0.0"))]
	elif humans() >= int(server_info.get("max", 12)):
		reason = "The server is full."
	if reason != "":
		rejected.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(func(): if _peer: _peer.disconnect_peer(id))
		return
	var p := {"name": str(profile.get("name", "Player")).substr(0, 20), "shirt": profile.get("shirt", Color.GRAY),
		"pants": profile.get("pants", Color.DIM_GRAY), "skin": profile.get("skin", Color.BISQUE), "kills": 0, "deaths": 0, "bot": false,
		"look": Cosmetics.sanitize(profile.get("look", {})), "hair": _color_or(profile.get("hair"), Cosmetics.DEFAULT_HAIR)}
	players[id] = p
	welcome.rpc_id(id, server_info)
	broadcast_players()


## `value` if it is a Color, otherwise `fallback` (profiles come from the network).
static func _color_or(value: Variant, fallback: Color) -> Color:
	return value if value is Color else fallback


func broadcast_players() -> void:
	if multiplayer.is_server():
		set_players.rpc(players)


@rpc("authority", "call_local", "reliable")
func set_players(list: Dictionary) -> void:
	players = list
	players_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		# Wait one frame so the match can still show the name of the player who left.
		(func():
			players.erase(id)
			broadcast_players()).call_deferred()


# ------------------------------------------------------------------ client

func join(ip: String, code := "") -> void:
	leave()
	_join_code = code
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, PORT)
	if err != OK:
		_peer = null
		join_failed.emit("Invalid address: " + ip)
		return
	multiplayer.multiplayer_peer = _peer


func _on_connected() -> void:
	register.rpc_id(1, Config.profile(), _join_code)


@rpc("authority", "reliable")
func welcome(info: Dictionary) -> void:
	# A 1.0 server does not check versions and sends none: refuse it here.
	if str(info.get("version", "")) != GAME_VERSION:
		leave()
		join_failed.emit("Version mismatch: the server runs OpenShooter %s, you have %s." % [
			str(info.get("version", "1.0.0")), GAME_VERSION])
		return
	server_info = info
	joined.emit()


@rpc("authority", "reliable")
func rejected(reason: String) -> void:
	leave()
	join_failed.emit(reason)


func leave() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	_send = null
	players.clear()


# ------------------------------------------------------------------ discovery

func start_listening() -> void:
	if _listen:
		return
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		push_warning("discovery port is busy")
		_listen = null


func stop_listening() -> void:
	if _listen:
		_listen.close()
	_listen = null
	found.clear()


func _process(delta: float) -> void:
	if _send and multiplayer.is_server():
		_broadcast_t -= delta
		if _broadcast_t <= 0.0:
			_broadcast_t = 1.0
			var msg := {
				"tag": GAME_TAG, "name": server_info.get("name", "Server"),
				"mode": server_info.get("mode", "normal"), "private": server_info.get("private", false),
				"hash": code_hash(server_info.get("code", "")), "players": humans(),
				"max": server_info.get("max", 12), "bots": server_info.get("bots", 0),
				"map": MapDB.display_name(int(server_info.get("map", 0))),
				"mode_name": ModeDB.get_mode(int(server_info.get("mode_idx", 0))).display_name,
			}
			var data := JSON.stringify(msg).to_utf8_buffer()
			for addr in ["255.255.255.255", "127.0.0.1"]:
				_send.set_dest_address(addr, DISCOVERY_PORT)
				_send.put_packet(data)
	if _listen:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var data := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var info = JSON.parse_string(data.get_string_from_utf8())
			if info is Dictionary and info.get("tag", "") == GAME_TAG:
				if ip == "127.0.0.1" or ip == "::1":
					ip = "127.0.0.1"
				info["ip"] = ip
				info["seen"] = Time.get_ticks_msec()
				found[ip] = info
				changed = true
		var now := Time.get_ticks_msec()
		for ip in found.keys():
			if now - int(found[ip].seen) > 3500:
				found.erase(ip)
				changed = true
		if changed:
			servers_changed.emit()
