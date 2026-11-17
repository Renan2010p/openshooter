extends Node
## Discord Rich Presence (autoload "Discord").
##
## Shows on the player's Discord profile what they are doing in OpenShooter:
## in the lobby, or the mode, map, level, eliminations and players of the
## current match, with the game logo and a download button.
##
## How it works: the Discord desktop app listens on a local channel
## (discord-ipc-0..9). The native module (DiscordIpc, native/src/
## discord_class.zig) opens it and moves frames; this script finds the
## channel, says hello (handshake), answers pings and sends the activity.
##
## Only on desktop (Windows, Linux, macOS) with the Discord app running.
## Nothing happens when Discord is closed; it reconnects when it opens.
## `--no-discord` turns it off.
##
## Images: the Discord application must have an Art Asset named "logo"
## (Developer Portal -> Rich Presence -> Art Assets; docs/discord/logo_1024.png).

## OpenShooter's application on the Discord Developer Portal.
const CLIENT_ID := "1572272510903386242"
## Art Asset key of the big image.
const LARGE_IMAGE := "logo"
const DOWNLOAD_URL := "https://github.com/Renan2010p/openshooter/releases/latest"

## Frame opcodes of the Discord IPC protocol.
const OP_HANDSHAKE := 0
const OP_FRAME := 1
const OP_CLOSE := 2
const OP_PING := 3
const OP_PONG := 4

## Seconds between connection attempts while Discord is not reachable.
const RECONNECT_SECONDS := 15.0
## Seconds between activity checks. Discord accepts at most 5 updates every
## 20 seconds; an update is only sent when something changed.
const UPDATE_SECONDS := 5.0

var _ipc: RefCounted
## True after Discord answered the handshake (READY).
var _ready_ok := false
var _reconnect_t := 0.0
var _update_t := 0.0
var _last_sent := ""
var _nonce := 0
## Unix time when the game started and when the current match started.
var _game_start := int(Time.get_unix_time_from_system())
var _match_start := 0
var _in_match := false


func _ready() -> void:
	var desktop := OS.has_feature("pc") and not OS.has_feature("web")
	if CLIENT_ID == "" or not desktop or not ClassDB.class_exists("DiscordIpc") \
			or "--no-discord" in OS.get_cmdline_user_args():
		set_process(false)
		return
	_ipc = ClassDB.instantiate("DiscordIpc")
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if _ipc and _ipc.is_open():
		_ipc.send(OP_CLOSE, "{}")
		_ipc.close()


func _process(delta: float) -> void:
	if not _ipc.is_open():
		_ready_ok = false
		_last_sent = ""
		_reconnect_t -= delta
		if _reconnect_t <= 0.0:
			_reconnect_t = RECONNECT_SECONDS
			_connect()
		return
	_read_frames()
	if not _ready_ok:
		return
	_update_t -= delta
	if _update_t <= 0.0:
		_update_t = UPDATE_SECONDS
		_send_activity()


# ============================================================================
# Connection
# ============================================================================

## Tries every place the Discord app may have opened its channel, then says
## hello. The answer (READY) arrives a moment later in _read_frames().
func _connect() -> void:
	for path in _candidate_paths():
		if _ipc.open(path):
			_ipc.send(OP_HANDSHAKE, JSON.stringify({"v": 1, "client_id": CLIENT_ID}))
			return


## Possible channel locations, most common first.
func _candidate_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	if OS.get_name() == "Windows":
		for i in 10:
			paths.append("\\\\?\\pipe\\discord-ipc-%d" % i)
		return paths
	# Linux / macOS / FreeBSD: a socket in the user's runtime or temp folder.
	var bases := PackedStringArray()
	for variable in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]:
		var value := OS.get_environment(variable)
		if value != "" and not value in bases:
			bases.append(value.trim_suffix("/"))
	bases.append("/tmp")
	# The regular app, then the Flatpak, Snap and Vesktop builds.
	var folders := ["", "app/com.discordapp.Discord/", ".flatpak/com.discordapp.Discord/xdg-run/",
		"snap.discord/", "app/dev.vencord.Vesktop/"]
	for i in 10:
		for base in bases:
			for folder in folders:
				paths.append("%s/%sdiscord-ipc-%d" % [base, folder, i])
	return paths


## Handles everything Discord sent: READY, pings and close.
func _read_frames() -> void:
	while true:
		var text: String = _ipc.receive()
		if text == "":
			return
		match _ipc.last_opcode():
			OP_PING:
				_ipc.send(OP_PONG, text)
			OP_CLOSE:
				_ipc.close()
				return
			OP_FRAME:
				var message = JSON.parse_string(text)
				if message is Dictionary and message.get("evt") == "READY":
					_ready_ok = true
					_update_t = 0.0  # send the activity right away
				elif message is Dictionary and message.get("evt") == "ERROR":
					push_warning("Discord: %s" % message.get("data", {}).get("message", "error"))


# ============================================================================
# Activity
# ============================================================================

func _send_activity() -> void:
	var activity := _activity()
	var key := JSON.stringify(activity)
	if key == _last_sent:
		return
	_last_sent = key
	_nonce += 1
	_ipc.send(OP_FRAME, JSON.stringify({
		"cmd": "SET_ACTIVITY",
		"args": {"pid": OS.get_process_id(), "activity": activity},
		"nonce": str(_nonce),
	}))


## What the profile shows now.
func _activity() -> Dictionary:
	var level: int = Progression.level_info(Config.xp).level
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	var activity := {
		"assets": {"large_image": LARGE_IMAGE, "large_text": "OpenShooter %s" % version},
		"buttons": [{"label": "Download OpenShooter", "url": DOWNLOAD_URL}],
	}
	var world := get_tree().root.get_node_or_null("Main/World") as World
	var in_match := world != null and is_instance_valid(world.map)
	if in_match != _in_match:
		_in_match = in_match
		_match_start = int(Time.get_unix_time_from_system())
	if in_match:
		var mode := ModeDB.get_mode(world.mode_index).display_name
		var me: Dictionary = Net.players.get(multiplayer.get_unique_id(), {})
		var kills := int(me.get("kills", 0))
		activity["details"] = "%s · %s" % [mode, MapDB.display_name(world.map_index)]
		activity["state"] = "Level %d · %d elimination%s" % [level, kills, "" if kills == 1 else "s"]
		activity["timestamps"] = {"start": _match_start}
		var humans := 0
		for id in Net.players:
			if not Net.players[id].get("bot", false):
				humans += 1
		activity["party"] = {"id": "match-%d" % _match_start, "size": [maxi(humans, 1), int(Net.server_info.get("max", 12))]}
	else:
		activity["details"] = "In the lobby"
		activity["state"] = "Level %d" % level
		activity["timestamps"] = {"start": _game_start}
	return activity
