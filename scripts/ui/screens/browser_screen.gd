extends MenuScreen
## Lista de servidores públicos achados na rede local (modo Normal ou Duelos).

const ROW_SCENE := preload("res://scenes/ui/server_row.tscn")
const TITLES := {"normal": "SERVIDORES NA REDE — NORMAL", "duel": "SERVIDORES NA REDE — APENAS DUELOS"}

var mode := "normal"


func _ready() -> void:
	bind_button(%Create, func(): menu.show_screen("Create", mode))
	bind_button(%Connect, _connect_direct)
	bind_button(%Back, func(): menu.show_screen("Modes"))
	%DirectIp.text_submitted.connect(func(_t): _connect_direct())
	Net.servers_changed.connect(_refresh)


func enter(arg: Variant) -> void:
	mode = str(arg) if arg != null else "normal"
	%Title.text = TITLES.get(mode, "SERVIDORES")
	_refresh()


func _connect_direct() -> void:
	var ip: String = %DirectIp.text.strip_edges()
	if ip != "":
		menu.request_join(ip)


func _refresh() -> void:
	if not visible:
		return
	var list: VBoxContainer = %ServerList
	for c in list.get_children():
		c.queue_free()
	var any := false
	for ip in Net.found:
		var s: Dictionary = Net.found[ip]
		if s.get("private", false) or s.get("mode", "") != mode:
			continue
		any = true
		var row: ServerRow = ROW_SCENE.instantiate()
		list.add_child(row)
		row.setup(ip, s)
		row.join_pressed.connect(func(addr): menu.request_join(addr))
	%Empty.visible = not any
