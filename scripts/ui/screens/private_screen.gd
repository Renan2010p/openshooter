extends MenuScreen
## Jogo privado: entrar com um código de 5 números ou criar um servidor privado.

## Por quanto tempo procurar o servidor na rede antes de desistir.
@export var search_seconds := 4.0

var _pending := ""
var _search_t := 0.0


func _ready() -> void:
	bind_button(%Join, _start_search)
	bind_button(%Create, func(): menu.show_screen("Create", "private"))
	bind_button(%Back, func(): menu.show_screen("Modes"))
	%Code.text_submitted.connect(func(_t): _start_search())


func leave() -> void:
	_pending = ""


func _start_search() -> void:
	var code: String = %Code.text.strip_edges()
	if code.length() != 5 or not code.is_valid_int():
		menu.set_status("O código tem 5 números.")
		return
	_pending = code
	_search_t = search_seconds
	menu.set_status("Procurando o servidor %s na rede..." % code, true)


func _process(delta: float) -> void:
	if _pending == "":
		return
	var h := Net.code_hash(_pending)
	for ip in Net.found:
		if Net.found[ip].get("hash", "") == h:
			var code := _pending
			_pending = ""
			menu.request_join(ip, code)
			return
	_search_t -= delta
	if _search_t <= 0.0:
		_pending = ""
		menu.set_status("Nenhum servidor privado com esse código foi encontrado na rede.")
