class_name GameMap
extends Node3D
## Mapa "Bairro": casas com portas e janelas, galpão com rampa, sebes, caixas e árvores.

const HALF := 40.0

var spawns: Array[Vector3] = []
var waypoints: Array[Vector3] = []

var _grass: StandardMaterial3D
var _body: StaticBody3D
var sun: DirectionalLight3D
var env: Environment


func build() -> void:
	_environment()
	_ground()
	# Muro em volta do mapa.
	var brick := Models.mat(Color(0.55, 0.32, 0.26))
	solid(Vector3(0, 2, -HALF), Vector3(HALF * 2, 4, 1), brick)
	solid(Vector3(0, 2, HALF), Vector3(HALF * 2, 4, 1), brick)
	solid(Vector3(-HALF, 2, 0), Vector3(1, 4, HALF * 2), brick)
	solid(Vector3(HALF, 2, 0), Vector3(1, 4, HALF * 2), brick)

	house(Vector3(-25, 0, -25), Vector2(11, 8), 3.4, Color(0.55, 0.7, 0.9), [["s", 0.0, 1.6], ["e", 1.5, 1.4]], [["s", -3.5, 1.4], ["s", 3.5, 1.4], ["n", 0.0, 2.0], ["w", 0.0, 1.6]])
	house(Vector3(25, 0, -25), Vector2(9, 10), 3.4, Color(0.92, 0.85, 0.6), [["s", -2.0, 1.6], ["w", 2.0, 1.4]], [["s", 2.5, 1.4], ["e", -2.0, 1.6], ["n", 0.0, 2.0]])
	house(Vector3(-25, 0, 25), Vector2(10, 9), 3.4, Color(0.85, 0.55, 0.5), [["n", 1.5, 1.6], ["e", -1.0, 1.4]], [["n", -3.0, 1.4], ["s", 0.0, 2.2], ["w", 1.0, 1.4]])
	house(Vector3(25, 0, 25), Vector2(11, 8), 3.4, Color(0.7, 0.85, 0.65), [["n", -2.5, 1.6], ["w", 0.0, 1.4]], [["n", 2.5, 1.4], ["s", -2.0, 1.6], ["s", 2.5, 1.6], ["e", 0.0, 1.6]])
	_warehouse()

	# Sebes (cobertura baixa e alta).
	var hedge := Models.mat(Color(0.18, 0.42, 0.22))
	for p in [[Vector3(-12, 0, -14), Vector3(10, 2.2, 1.2)], [Vector3(12, 0, 14), Vector3(10, 2.2, 1.2)],
			[Vector3(-30, 0, 0), Vector3(1.2, 2.2, 12)], [Vector3(30, 0, 0), Vector3(1.2, 2.2, 12)],
			[Vector3(0, 0, -32), Vector3(14, 1.2, 1.0)], [Vector3(0, 0, 32), Vector3(14, 1.2, 1.0)]]:
		solid(p[0] + Vector3(0, p[1].y / 2.0, 0), p[1], hedge)
	# Muretas de concreto.
	var concrete := Models.mat(Color(0.6, 0.6, 0.6))
	for p in [Vector3(-16, 0.5, 6), Vector3(16, 0.5, -6), Vector3(-6, 0.5, 17), Vector3(6, 0.5, -17)]:
		solid(p, Vector3(4, 1.0, 0.5), concrete)
	# Pilhas de caixas.
	var crate := Models.mat(Color(0.62, 0.45, 0.25))
	for c in [Vector3(-14, 0, -4), Vector3(14, 0, 5), Vector3(-5, 0, 24), Vector3(6, 0, -25), Vector3(-34, 0, -12), Vector3(34, 0, 12), Vector3(-8, 0, -22), Vector3(10, 0, 22)]:
		solid(c + Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.2), crate)
		solid(c + Vector3(1.25, 0.6, 0.1), Vector3(1.2, 1.2, 1.2), crate, Vector3(0, 12, 0))
		solid(c + Vector3(0.6, 1.8, 0.05), Vector3(1.2, 1.2, 1.2), crate, Vector3(0, -8, 0))
	# Árvores.
	for t in [Vector3(-18, 0, -32), Vector3(18, 0, 32), Vector3(-34, 0, 18), Vector3(34, 0, -18), Vector3(-10, 0, 10), Vector3(10, 0, -10), Vector3(-34, 0, -32), Vector3(33, 0, 33)]:
		tree(t)
	# Carro estacionado (cobertura).
	solid(Vector3(-4, 0.6, -9), Vector3(4.2, 0.8, 1.9), Models.mat(Color(0.75, 0.15, 0.12), 0.4, 0.4))
	solid(Vector3(-4.3, 1.3, -9), Vector3(2.2, 0.7, 1.7), Models.mat(Color(0.25, 0.35, 0.45), 0.2, 0.3))
	for w in [Vector3(-5.4, 0.3, -8.0), Vector3(-2.6, 0.3, -8.0), Vector3(-5.4, 0.3, -10.0), Vector3(-2.6, 0.3, -10.0)]:
		Models.cyl(self, 0.32, 0.25, w, Models.mat(Color(0.08, 0.08, 0.08)), Vector3(90, 0, 0))

	# Centenas de caixas viram um único mesh (1-2 draw calls).
	Models.bake(self)
	Config.apply_quality(self)

	for x in [-34.0, -18.0, 0.0, 18.0, 34.0]:
		for z in [-34.0, 34.0]:
			spawns.append(Vector3(x, 0.2, z))
	for z in [-18.0, 0.0, 18.0]:
		spawns.append(Vector3(-36, 0.2, z))
		spawns.append(Vector3(36, 0.2, z))
	for x in range(-32, 33, 8):
		for z in range(-32, 33, 8):
			var p := Vector3(x, 0.2, z)
			if absf(x) < 9 and absf(z) < 7:
				continue
			if absf(absf(x) - 25) < 7 and absf(absf(z) - 25) < 7:
				continue
			waypoints.append(p)


func _environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.48, 0.85)
	sm.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sm.ground_horizon_color = Color(0.75, 0.82, 0.9)
	sm.ground_bottom_color = Color(0.4, 0.42, 0.45)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.0025
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 35.0
	add_child(sun)


func _ground() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.36, 0.6, 0.38))
	img.fill_rect(Rect2i(0, 0, 32, 32), Color(0.4, 0.66, 0.42))
	img.fill_rect(Rect2i(32, 32, 32, 32), Color(0.4, 0.66, 0.42))
	img.generate_mipmaps()
	_grass = StandardMaterial3D.new()
	_grass.albedo_texture = ImageTexture.create_from_image(img)
	_grass.uv1_triplanar = true
	_grass.uv1_scale = Vector3(0.25, 0.25, 0.25)
	_grass.roughness = 1.0
	solid(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), _grass)
	# Caminhos de terra.
	var dirt := Models.mat(Color(0.62, 0.55, 0.42))
	Models.box(self, Vector3(4, 0.02, HALF * 2 - 2), Vector3(0, 0.01, 0), dirt)
	Models.box(self, Vector3(HALF * 2 - 2, 0.02, 4), Vector3(0, 0.011, 0), dirt)


## Bloco sólido com colisão (camada 1 = mundo). Todas as colisões ficam num único
## StaticBody e o desenho é juntado num mesh só no fim de build().
func solid(pos: Vector3, size: Vector3, m: Material, rot := Vector3.ZERO) -> void:
	if _body == null:
		_body = StaticBody3D.new()
		_body.collision_layer = 1
		_body.collision_mask = 0
		add_child(_body)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position = pos
	shape.rotation_degrees = rot
	_body.add_child(shape)
	Models.box(self, size, pos, m, rot)


## Parede ao longo de um eixo com aberturas [a0, a1, y0, y1].
func wall(horizontal: bool, fixed: float, a0: float, a1: float, h: float, gaps: Array, m: Material, t := 0.3) -> void:
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	var cur := a0
	for g in gaps:
		if g[0] > cur:
			_seg(horizontal, fixed, cur, g[0], 0.0, h, m, t)
		if g[2] > 0.0:
			_seg(horizontal, fixed, g[0], g[1], 0.0, g[2], m, t)
		if g[3] < h:
			_seg(horizontal, fixed, g[0], g[1], g[3], h, m, t)
		cur = maxf(cur, g[1])
	if cur < a1:
		_seg(horizontal, fixed, cur, a1, 0.0, h, m, t)


func _seg(horizontal: bool, fixed: float, a: float, b: float, y0: float, y1: float, m: Material, t: float) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01:
		return
	var mid := (a + b) / 2.0
	if horizontal:
		solid(Vector3(mid, (y0 + y1) / 2.0, fixed), Vector3(b - a, y1 - y0, t), m)
	else:
		solid(Vector3(fixed, (y0 + y1) / 2.0, mid), Vector3(t, y1 - y0, b - a), m)


## Casa com portas [lado, deslocamento, largura] e janelas.
func house(c: Vector3, size: Vector2, h: float, color: Color, doors: Array, windows: Array) -> void:
	var m := Models.mat(color)
	var x0 := c.x - size.x / 2.0
	var x1 := c.x + size.x / 2.0
	var z0 := c.z - size.y / 2.0
	var z1 := c.z + size.y / 2.0
	var gaps := {"n": [], "s": [], "w": [], "e": []}
	for d in doors:
		var center: float = (c.x if d[0] in ["n", "s"] else c.z) + d[1]
		gaps[d[0]].append([center - d[2] / 2.0, center + d[2] / 2.0, 0.0, 2.3])
	for w in windows:
		var center: float = (c.x if w[0] in ["n", "s"] else c.z) + w[1]
		gaps[w[0]].append([center - w[2] / 2.0, center + w[2] / 2.0, 1.0, 2.1])
	wall(true, z0, x0, x1, h, gaps.n, m)
	wall(true, z1, x0, x1, h, gaps.s, m)
	wall(false, x0, z0, z1, h, gaps.w, m)
	wall(false, x1, z0, z1, h, gaps.e, m)
	solid(Vector3(c.x, h + 0.15, c.z), Vector3(size.x + 0.6, 0.3, size.y + 0.6), Models.mat(color.darkened(0.45)))
	Models.box(self, Vector3(size.x - 0.4, 0.02, size.y - 0.4), Vector3(c.x, 0.02, c.z), Models.mat(Color(0.5, 0.38, 0.28)))
	# Móveis simples para cobertura.
	solid(Vector3(c.x - size.x / 4.0, 0.45, c.z), Vector3(1.6, 0.9, 0.8), Models.mat(Color(0.4, 0.28, 0.2)))
	solid(Vector3(c.x + size.x / 4.0, 0.9, c.z - size.y / 2.0 + 0.6), Vector3(1.4, 1.8, 0.6), Models.mat(Color(0.35, 0.3, 0.3)))


func _warehouse() -> void:
	var m := Models.mat(Color(0.5, 0.52, 0.55))
	var h := 5.0
	wall(true, -5.0, -7.0, 7.0, h, [[-1.75, 1.75, 0.0, 3.5], [-5.5, -3.8, 2.0, 3.2], [3.8, 5.5, 2.0, 3.2]], m)
	wall(true, 5.0, -7.0, 7.0, h, [[-1.75, 1.75, 0.0, 3.5], [-5.5, -3.8, 2.0, 3.2], [3.8, 5.5, 2.0, 3.2]], m)
	wall(false, -7.0, -5.0, 5.0, h, [[-1.0, 1.0, 1.4, 2.6]], m)
	wall(false, 7.0, -5.0, 5.0, h, [[-1.0, 1.0, 0.0, 2.6]], m)
	solid(Vector3(0, h + 0.15, 0), Vector3(14.6, 0.3, 10.6), Models.mat(Color(0.3, 0.32, 0.35)))
	# Parapeito no telhado.
	var rail := Models.mat(Color(0.4, 0.4, 0.42))
	solid(Vector3(0, h + 0.75, -5.15), Vector3(14.6, 0.9, 0.3), rail)
	solid(Vector3(0, h + 0.75, 5.15), Vector3(14.6, 0.9, 0.3), rail)
	solid(Vector3(-7.15, h + 0.75, 0), Vector3(0.3, 0.9, 10.6), rail)
	# Rampa até o telhado (lado leste, de fora).
	var ramp_len := 12.0
	var ang := rad_to_deg(atan2(h + 0.3, ramp_len))
	solid(Vector3(7.4 + ramp_len / 2.0 - 0.3, (h + 0.3) / 2.0, 3.6), Vector3(sqrt(ramp_len * ramp_len + (h + 0.3) * (h + 0.3)), 0.3, 2.2), Models.mat(Color(0.45, 0.35, 0.25)), Vector3(0, 0, -ang))
	# Caixas dentro do galpão.
	var crate := Models.mat(Color(0.62, 0.45, 0.25))
	for p in [Vector3(-4, 0.75, 0), Vector3(4, 0.75, -2), Vector3(0, 0.75, 2.5)]:
		solid(p, Vector3(1.5, 1.5, 1.5), crate)


func tree(p: Vector3) -> void:
	solid(p + Vector3(0, 1.5, 0), Vector3(0.6, 3.0, 0.6), Models.mat(Color(0.4, 0.28, 0.18)))
	var leaf := Models.mat(Color(0.2, 0.45, 0.28))
	solid(p + Vector3(0, 3.6, 0), Vector3(3.0, 1.6, 3.0), leaf)
	Models.box(self, Vector3(2.0, 1.2, 2.0), p + Vector3(0.3, 4.8, -0.2), leaf)


## Ponto de nascimento longe dos inimigos.
func best_spawn(avoid: Array) -> Vector3:
	var best := spawns[randi() % spawns.size()]
	var best_d := -1.0
	for s in spawns:
		var d := 1e9
		for a in avoid:
			d = minf(d, s.distance_to(a))
		d += randf() * 6.0
		if d > best_d:
			best_d = d
			best = s
	return best
