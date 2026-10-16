extends Node2D

var radius := 170.0          # raio da área escolhida
var bolt_count := 2          # quantidade de raios (vem do level)
var damage := 25
var hit_radius := 45.0       # área de dano de cada raio

const ISO := 0.55
const WARN_TIME := 0.7       # tempo de aviso antes de cair
const STRIKE_GAP := 0.14     # intervalo entre os raios
const FX_TIME := 0.35        # duração visual de cada raio
const SKY_HEIGHT := 700.0
const BOLT_SEGS := 12
const FLICKER_TIME := 0.05
const RING_POINTS := 40

const COL_CORE := Color(1, 1, 1)
const COL_MID := Color(0.45, 0.85, 1)
const COL_OUT := Color(0.4, 0.3, 1)

static var glow_tex: GradientTexture2D

var t := 0.0
var life_total := 0.0
var flicker_timer := 0.0

var s_pos := PackedVector2Array()
var s_time := PackedFloat32Array()
var s_fired := PackedByteArray()
var s_bolt: Array[PackedVector2Array] = []
var ring_pts := PackedVector2Array()


func _ready():
	randomize()
	# Keep exported/runtime overrides safe before allocating per-strike arrays.
	radius = maxf(radius, 1.0)
	bolt_count = maxi(bolt_count, 1)
	hit_radius = maxf(hit_radius, 1.0)
	damage = maxi(damage, 0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_get_glow()
	ring_pts.resize(RING_POINTS + 1)

	s_pos.resize(bolt_count)
	s_time.resize(bolt_count)
	s_fired.resize(bolt_count)
	s_bolt.resize(bolt_count)
	for i in bolt_count:
		# ponto aleatório dentro da elipse da área (achatada pelo ISO)
		var a: float = randf() * TAU
		var d: float = sqrt(randf()) * radius * 0.9
		s_pos[i] = Vector2(cos(a) * d, sin(a) * d * ISO)
		s_time[i] = WARN_TIME + i * STRIKE_GAP + randf_range(0.0, 0.06)
		s_fired[i] = 0
		s_bolt[i] = PackedVector2Array()
	life_total = WARN_TIME + bolt_count * STRIKE_GAP + FX_TIME + 0.15


# ---------- helpers ----------
static func _get_glow() -> GradientTexture2D:
	if glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
		glow_tex = GradientTexture2D.new()
		glow_tex.gradient = g
		glow_tex.fill = GradientTexture2D.FILL_RADIAL
		glow_tex.fill_from = Vector2(0.5, 0.5)
		glow_tex.fill_to = Vector2(1.0, 0.5)
		glow_tex.width = 128
		glow_tex.height = 128
	return glow_tex

func _glow(center: Vector2, r: float, col: Color, squash := 1.0):
	if r <= 0.5 or col.a <= 0.01:
		return
	draw_texture_rect(glow_tex, Rect2(center.x - r, center.y - r * squash, r * 2.0, r * 2.0 * squash), false, col)

func _make_bolt(start: Vector2, end: Vector2, segs: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	segs = maxi(segs, 1)
	pts.resize(segs + 1)
	var dir: Vector2 = (end - start)
	var normal: Vector2 = dir.normalized().orthogonal()
	for i in segs + 1:
		var k: float = float(i) / segs
		var env: float = sin(k * PI)
		pts[i] = start + dir * k + normal * randf_range(-1.0, 1.0) * jitter * env
	return pts

func _regen_bolt(i: int):
	var ground: Vector2 = s_pos[i]
	var start: Vector2 = ground + Vector2(randf_range(-40.0, 40.0), -SKY_HEIGHT)
	s_bolt[i] = _make_bolt(start, ground, BOLT_SEGS, 22.0)

func _apply_damage(i: int):
	var center: Vector2 = to_global(s_pos[i])
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D):
			continue
		var d: Vector2 = e.global_position - center
		# mesma elipse do visual (achatada pelo ISO)
		if d.x * d.x + (d.y / ISO) * (d.y / ISO) <= hit_radius * hit_radius:
			if e.has_method("take_damage"):
				e.take_damage(damage)


# ---------- update ----------
func _process(delta):
	t += delta

	var do_flicker := false
	flicker_timer += delta
	if flicker_timer >= FLICKER_TIME:
		flicker_timer = 0.0
		do_flicker = true

	for i in bolt_count:
		if s_fired[i] == 0 and t >= s_time[i]:
			s_fired[i] = 1
			_regen_bolt(i)
			_apply_damage(i)
		elif s_fired[i] == 1 and do_flicker and t - s_time[i] < FX_TIME:
			_regen_bolt(i)

	queue_redraw()
	if t >= life_total:
		queue_free()


# ---------- desenho ----------
func _draw():
	var fade_duration: float = maxf(life_total - WARN_TIME, 0.001)
	var fade: float = 1.0 - clampf((t - WARN_TIME) / fade_duration, 0.0, 1.0)
	fade = clampf(fade * 1.5, 0.0, 1.0)

	_draw_area(fade)

	for i in bolt_count:
		if s_fired[i] == 0:
			_draw_marker(i)
		else:
			var age: float = t - s_time[i]
			if age < FX_TIME:
				_draw_strike(i, age)

func _draw_area(fade: float):
	var warn: float = clampf(t / WARN_TIME, 0.0, 1.0)
	var pulse: float = 0.75 + 0.25 * sin(t * 18.0)
	var a: float = fade * (0.35 + 0.65 * warn) * pulse

	_glow(Vector2.ZERO, radius * 1.2, Color(COL_OUT, a * 0.35), ISO)
	_glow(Vector2.ZERO, radius * 0.7, Color(COL_MID, a * 0.2), ISO)

	# anel serrilhado que gira
	for i in RING_POINTS + 1:
		var k: int = i % RING_POINTS
		var ang: float = TAU * k / RING_POINTS + t * 0.8
		var wob: float = 1.0 + (0.025 if k % 2 == 0 else -0.025)
		ring_pts[i] = Vector2(cos(ang), sin(ang) * ISO) * radius * wob
	draw_polyline(ring_pts, Color(COL_OUT, a * 0.4), 4.0)
	draw_polyline(ring_pts, Color(COL_MID, a * 0.9), 1.6, true)

func _draw_marker(i: int):
	# anel que fecha no ponto onde o raio vai cair
	var p: Vector2 = s_pos[i]
	var k: float = clampf(t / s_time[i], 0.0, 1.0)
	var r: float = lerpf(hit_radius * 1.5, hit_radius * 0.5, k)
	var a: float = 0.3 + 0.7 * k
	_glow(p, hit_radius * 1.1, Color(COL_MID, a * 0.25), ISO)
	draw_set_transform(p, 0.0, Vector2(1.0, ISO))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(COL_MID, a), 1.6, true)
	draw_arc(Vector2.ZERO, r * 0.4, 0.0, TAU, 16, Color(COL_CORE, a), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_strike(i: int, age: float):
	var a: float = pow(1.0 - age / FX_TIME, 0.7)
	var p: Vector2 = s_pos[i]
	var pts: PackedVector2Array = s_bolt[i]

	# raio vertical: halo, corpo, núcleo fino
	draw_polyline(pts, Color(COL_OUT, a * 0.30), 7.0)
	draw_polyline(pts, Color(COL_MID, a * 0.85), 2.8, true)
	draw_polyline(pts, Color(COL_CORE, a), 1.2, true)

	# brilho no impacto + flash no chão
	_glow(p, hit_radius * 1.8 * a, Color(COL_MID, a * 0.7), ISO)
	_glow(p, hit_radius * 0.7 * a, Color(COL_CORE, a), ISO)

	# onda de choque expandindo
	var k: float = age / FX_TIME
	draw_set_transform(p, 0.0, Vector2(1.0, ISO))
	draw_arc(Vector2.ZERO, hit_radius * (0.3 + k * 1.1), 0.0, TAU, 24, Color(COL_MID, a * 0.9), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# faíscas curtas saindo do impacto
	for n in 6:
		var ang: float = n * TAU / 6.0 + float(i) * 1.7
		var dir := Vector2(cos(ang), sin(ang) * ISO)
		draw_line(p + dir * hit_radius * 0.3 * k, p + dir * hit_radius * (0.5 + k) * 0.9,
			Color(COL_CORE, a), 1.2)
