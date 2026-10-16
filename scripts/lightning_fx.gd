extends Node2D

var length := 600.0
var direction := Vector2.RIGHT
var life := 0.0

const DURATION := 0.35
const SEGMENTS := 20
const BRANCH_SEGS := 6
const JITTER := 22.0
const FLICKER_TIME := 0.05
const BRANCH_COUNT := 3
const DROP_COUNT := 30
const SPREAD := 35.0
const GRAVITY := 900.0

const COL_CORE := Color(1, 1, 1)
const COL_MID := Color(0.45, 0.85, 1)
const COL_OUT := Color(0.4, 0.3, 1)

static var glow_tex: GradientTexture2D   # textura de brilho compartilhada

var main_points := PackedVector2Array()
var branches: Array[PackedVector2Array] = []
var flicker_timer := 0.0
var end_point := Vector2.ZERO

# gotas em arrays paralelos (mais rápido que dicionários)
var dr_pos := PackedVector2Array()
var dr_vel := PackedVector2Array()
var dr_size := PackedFloat32Array()
var dr_len := PackedFloat32Array()
var dr_delay := PackedFloat32Array()


func _ready():
	randomize()
	# Blend aditivo: o brilho acende o que está atrás
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

	_get_glow()
	_generate_bolt()
	_spawn_drops()


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

# Brilho suave com UMA chamada de desenho
func _glow(center: Vector2, r: float, col: Color):
	if r <= 0.5 or col.a <= 0.01:
		return
	draw_texture_rect(glow_tex, Rect2(center.x - r, center.y - r, r * 2.0, r * 2.0), false, col)


# ---------- geração (só roda a cada FLICKER_TIME) ----------
func _make_bolt(start: Vector2, dir: Vector2, len: float, segments: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segments + 1)
	var normal: Vector2 = dir.orthogonal()
	for i in segments + 1:
		var t: float = float(i) / segments
		var env: float = sin(t * PI)   # 0 nas pontas: início e fim ficam no lugar
		pts[i] = start + dir * len * t + normal * randf_range(-1.0, 1.0) * jitter * env
	return pts

func _generate_bolt():
	main_points = _make_bolt(Vector2.ZERO, direction, length, SEGMENTS, JITTER)
	end_point = main_points[main_points.size() - 1]
	branches.clear()
	for i in BRANCH_COUNT:
		var idx: int = randi_range(4, SEGMENTS - 4)
		var angle: float = deg_to_rad(randf_range(20.0, 40.0)) * (1.0 if randf() > 0.5 else -1.0)
		var b_len: float = randf_range(60.0, 140.0)
		branches.append(_make_bolt(main_points[idx], direction.rotated(angle), b_len, BRANCH_SEGS, JITTER * 0.6))

func _spawn_drops():
	dr_pos.resize(DROP_COUNT)
	dr_vel.resize(DROP_COUNT)
	dr_size.resize(DROP_COUNT)
	dr_len.resize(DROP_COUNT)
	dr_delay.resize(DROP_COUNT)
	for i in DROP_COUNT:
		var p: Vector2 = main_points[randi() % main_points.size()]
		dr_pos[i] = p + Vector2(randf_range(-SPREAD, SPREAD), randf_range(-SPREAD, SPREAD))
		dr_vel[i] = Vector2(randf_range(-30.0, 30.0), randf_range(-60.0, 40.0))
		dr_size[i] = randf_range(0.8, 1.8)
		dr_len[i] = randf_range(6.0, 16.0)
		dr_delay[i] = randf_range(0.0, 0.4)


# ---------- update ----------
func _process(delta):
	life += delta / DURATION

	flicker_timer += delta
	if flicker_timer >= FLICKER_TIME:
		flicker_timer = 0.0
		_generate_bolt()

	for i in DROP_COUNT:
		if life > dr_delay[i]:
			dr_vel[i].y += GRAVITY * delta
			dr_pos[i] += dr_vel[i] * delta

	queue_redraw()
	if life >= 1.0:
		queue_free()


# ---------- desenho ----------
func _draw():
	var alpha: float = 1.0 - life
	var a: float = pow(alpha, 0.7)

	# Brilho ao longo do raio (poucos pontos, uma chamada cada)
	var step: int = maxi(SEGMENTS / 4, 1)
	for i in range(0, main_points.size(), step):
		_glow(main_points[i], 40.0 * a, Color(COL_OUT, a * 0.18))

	# Raio principal: halo, corpo e núcleo fino
	_draw_poly(main_points, a, 1.0)

	# Ramificações
	for b in branches:
		_draw_poly(b, a, 0.55)

	# Gotas em volta
	for i in DROP_COUNT:
		if life < dr_delay[i]:
			continue
		var da: float = alpha * clampf(1.0 - (life - dr_delay[i]) * 1.2, 0.0, 1.0)
		if da <= 0.01:
			continue
		var pos: Vector2 = dr_pos[i]
		var tail: Vector2 = pos - dr_vel[i].normalized() * dr_len[i]
		draw_line(tail, pos, Color(COL_MID, da * 0.8), dr_size[i] * 1.6)
		draw_line(tail, pos, Color(COL_CORE, da), dr_size[i] * 0.7)

	# Impacto na ponta
	_glow(end_point, 36.0 * a, Color(COL_MID, a * 0.7))
	_glow(end_point, 12.0 * a, Color(COL_CORE, a))
	draw_arc(end_point, life * 45.0, 0.0, TAU, 20, Color(COL_MID, alpha * 0.8), 1.5, true)

func _draw_poly(pts: PackedVector2Array, a: float, s: float):
	draw_polyline(pts, Color(COL_OUT, a * 0.30), 6.0 * s)             # halo
	draw_polyline(pts, Color(COL_MID, a * 0.85), 2.4 * s, true)       # corpo
	draw_polyline(pts, Color(COL_CORE, a), 1.0 * s, true)             # núcleo fino
