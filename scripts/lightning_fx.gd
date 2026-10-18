extends Node2D

var length := 600.0
var direction := Vector2.RIGHT
var life := 0.0

const DURATION := 0.55
const STRIKE_TIME := 0.055
const SEGMENTS := 32
const BRANCH_SEGS := 8
const JITTER := 13.0
const FLICKER_TIME := 0.04
const BRANCH_COUNT := 5
const SPARK_COUNT := 75
const EMBER_COUNT := 30
const MOTE_COUNT := 32
const GRAVITY := 700.0
const SPREAD := 14.0
const IMPACT_CONE := 55.0            # graus — cone frontal das faíscas

const COL_CORE := Color(0.70, 0.94, 1.0)
const COL_MID  := Color(0.30, 0.68, 1.0)
const COL_OUT  := Color(0.10, 0.32, 0.95)
const COL_DEEP := Color(0.04, 0.10, 0.55)

static var glow_tex: GradientTexture2D

var main_points := PackedVector2Array()
var branches: Array[PackedVector2Array] = []
var branch_t := PackedFloat32Array()
var flicker_timer := 0.0
var flick := 1.0
var end_point := Vector2.ZERO

# faíscas
var sp_pos := PackedVector2Array()
var sp_vel := PackedVector2Array()
var sp_age := PackedFloat32Array()
var sp_max := PackedFloat32Array()
var sp_size := PackedFloat32Array()
var sp_delay := PackedFloat32Array()
var sp_phase := PackedFloat32Array()

# brasas
var em_pos := PackedVector2Array()
var em_vel := PackedVector2Array()
var em_max := PackedFloat32Array()
var em_size := PackedFloat32Array()

# poeira luminosa ao longo do feixe
var mot_pos := PackedVector2Array()
var mot_vel := PackedVector2Array()
var mot_phase := PackedFloat32Array()
var mot_size := PackedFloat32Array()


func _ready():
	randomize()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_get_glow()
	_generate_bolt()
	_spawn_sparks()
	_spawn_embers()
	_spawn_motes()


# ---------- helpers ----------
static func _get_glow() -> GradientTexture2D:
	if glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.1, 0.32, 0.62, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1.0),
			Color(1, 1, 1, 0.62),
			Color(1, 1, 1, 0.22),
			Color(1, 1, 1, 0.05),
			Color(1, 1, 1, 0.0)])
		glow_tex = GradientTexture2D.new()
		glow_tex.gradient = g
		glow_tex.fill = GradientTexture2D.FILL_RADIAL
		glow_tex.fill_from = Vector2(0.5, 0.5)
		glow_tex.fill_to = Vector2(1.0, 0.5)
		glow_tex.width = 256
		glow_tex.height = 256
	return glow_tex


func _glow(center: Vector2, r: float, col: Color):
	if r <= 0.5 or col.a <= 0.01:
		return
	draw_texture_rect(glow_tex, Rect2(center.x - r, center.y - r, r * 2.0, r * 2.0), false, col)


func _slice(pts: PackedVector2Array, f: float) -> PackedVector2Array:
	if f >= 1.0:
		return pts
	var n: int = pts.size()
	var pos: float = f * (n - 1)
	var whole: int = int(pos)
	var out := PackedVector2Array()
	for i in whole + 1:
		out.append(pts[i])
	if whole < n - 1:
		out.append(pts[whole].lerp(pts[whole + 1], pos - whole))
	return out


# ---------- geração ----------
func _make_bolt(start: Vector2, dir: Vector2, len_: float, segments: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segments + 1)
	var normal: Vector2 = dir.orthogonal()
	var drift := 0.0
	for i in segments + 1:
		var t: float = float(i) / segments
		var env: float = sin(t * PI)
		drift = clampf(drift + randf_range(-0.4, 0.4), -0.9, 0.9)
		var off: float = (drift * 0.75 + randf_range(-0.6, 0.6) * 0.4) * jitter * env
		pts[i] = start + dir * len_ * t + normal * off
	return pts


func _generate_bolt():
	main_points = _make_bolt(Vector2.ZERO, direction, length, SEGMENTS, JITTER)
	end_point = main_points[main_points.size() - 1]
	branches.clear()
	branch_t.clear()
	for i in BRANCH_COUNT:
		var idx: int = randi_range(5, SEGMENTS - 4)
		var angle: float = deg_to_rad(randf_range(8.0, 26.0)) * (1.0 if randf() > 0.5 else -1.0)
		var b_len: float = randf_range(35.0, 95.0)
		var bdir: Vector2 = direction.rotated(angle)
		var b := _make_bolt(main_points[idx], bdir, b_len, BRANCH_SEGS, JITTER * 0.55)
		branches.append(b)
		branch_t.append(float(idx) / SEGMENTS)
		if randf() < 0.6:
			var j: int = randi_range(2, BRANCH_SEGS - 2)
			branches.append(_make_bolt(b[j], bdir.rotated(randf_range(-0.6, 0.6)), b_len * 0.4, 4, JITTER * 0.3))
			branch_t.append(float(idx) / SEGMENTS + 0.03)


func _spawn_sparks():
	sp_pos.resize(SPARK_COUNT)
	sp_vel.resize(SPARK_COUNT)
	sp_age.resize(SPARK_COUNT)
	sp_max.resize(SPARK_COUNT)
	sp_size.resize(SPARK_COUNT)
	sp_delay.resize(SPARK_COUNT)
	sp_phase.resize(SPARK_COUNT)

	var base_ang := direction.angle()
	var cone := deg_to_rad(IMPACT_CONE)
	var perp := direction.orthogonal()
	var n_main := main_points.size()

	for i in SPARK_COUNT:
		var from_impact: bool = i < SPARK_COUNT * 3 / 5
		if from_impact:
			# Explosão em CONE FRONTAL — não espalha para os lados
			sp_pos[i] = end_point + Vector2(randf_range(-6, 6), randf_range(-6, 6))
			var ang: float = base_ang + randf_range(-cone, cone)
			sp_vel[i] = Vector2.from_angle(ang) * randf_range(180.0, 520.0)
			sp_delay[i] = STRIKE_TIME
		else:
			# Faíscas presas ao feixe, deriva lateral pequena
			var idx: int = randi() % n_main
			sp_pos[i] = main_points[idx] + Vector2(randf_range(-SPREAD, SPREAD), randf_range(-SPREAD, SPREAD))
			sp_vel[i] = perp * randf_range(-70.0, 70.0) + direction * randf_range(-30.0, 80.0)
			sp_delay[i] = STRIKE_TIME * (float(idx) / n_main)
		sp_age[i] = 0.0
		sp_max[i] = randf_range(0.18, 0.45)
		sp_size[i] = randf_range(0.6, 1.9)
		sp_phase[i] = randf() * TAU


func _spawn_embers():
	em_pos.resize(EMBER_COUNT)
	em_vel.resize(EMBER_COUNT)
	em_max.resize(EMBER_COUNT)
	em_size.resize(EMBER_COUNT)
	for i in EMBER_COUNT:
		var p: Vector2 = main_points[randi() % main_points.size()]
		em_pos[i] = p + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		em_vel[i] = Vector2(randf_range(-12.0, 12.0), randf_range(-30.0, -6.0))
		em_max[i] = randf_range(0.5, 0.9)
		em_size[i] = randf_range(4.0, 10.0)


func _spawn_motes():
	mot_pos.resize(MOTE_COUNT)
	mot_vel.resize(MOTE_COUNT)
	mot_phase.resize(MOTE_COUNT)
	mot_size.resize(MOTE_COUNT)
	for i in MOTE_COUNT:
		var idx: int = randi() % main_points.size()
		mot_pos[i] = main_points[idx] + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		mot_vel[i] = direction * randf_range(30.0, 90.0) + Vector2(randf_range(-15, 15), randf_range(-20, 8))
		mot_phase[i] = randf() * TAU
		mot_size[i] = randf_range(1.0, 3.0)


# ---------- update ----------
func _process(delta):
	life += delta / DURATION
	var t: float = life * DURATION

	flicker_timer += delta
	if flicker_timer >= FLICKER_TIME:
		flicker_timer = 0.0
		flick = randf_range(0.7, 1.0)
		_generate_bolt()

	for i in SPARK_COUNT:
		if t < sp_delay[i]:
			continue
		sp_age[i] += delta
		sp_vel[i] *= 1.0 - 3.0 * delta
		sp_vel[i].y += GRAVITY * delta
		sp_pos[i] += sp_vel[i] * delta
		sp_phase[i] += delta * 20.0

	for i in EMBER_COUNT:
		em_vel[i] *= 1.0 - 0.8 * delta
		em_pos[i] += em_vel[i] * delta

	for i in MOTE_COUNT:
		mot_pos[i] += mot_vel[i] * delta
		mot_vel[i] *= 1.0 - 2.5 * delta
		mot_phase[i] += delta * 16.0

	queue_redraw()
	if life >= 1.0:
		queue_free()


# ---------- desenho ----------
func _draw():
	var t: float = life * DURATION
	var reveal: float = clampf(t / STRIKE_TIME, 0.0, 1.0)
	var fade: float = pow(1.0 - life, 1.4)
	var flash: float = exp(-life * 14.0)
	var a: float = clampf(fade * flick + flash * 0.6, 0.0, 1.0)

	var shown: PackedVector2Array = _slice(main_points, reveal)

	# Clarão ambiente no impacto (3 camadas de blur)
	if flash > 0.02:
		_glow(end_point, 280.0 * flash + 60.0, Color(COL_DEEP, flash * 0.5))
		_glow(end_point, 160.0 * flash + 30.0, Color(COL_OUT, flash * 0.55))
		_glow(end_point, 80.0 * flash + 15.0, Color(COL_MID, flash * 0.5))

	# Emissão na ORIGEM — o poder sai daqui
	var origin_a := clampf(1.0 - t / (STRIKE_TIME * 2.0), 0.0, 1.0)
	if origin_a > 0.0:
		_glow(Vector2.ZERO, 90.0 * origin_a, Color(COL_DEEP, origin_a * 0.6))
		_glow(Vector2.ZERO, 50.0 * origin_a, Color(COL_OUT, origin_a * 0.7))
		_glow(Vector2.ZERO, 22.0 * origin_a, Color(COL_MID, origin_a * 0.8))
		_glow(Vector2.ZERO, 8.0 * origin_a, Color(COL_CORE, origin_a))

	# Halo difuso ao longo do feixe (blur acumulado)
	for i in range(0, shown.size(), 2):
		_glow(shown[i], 60.0 * a + 10.0, Color(COL_DEEP, a * 0.10))
		_glow(shown[i], 32.0 * a + 6.0, Color(COL_OUT, a * 0.16))
		_glow(shown[i], 14.0 * a + 3.0, Color(COL_MID, a * 0.16))

	# Feixe principal
	_draw_poly(shown, a, 1.0)

	# Ramos (curtos e fechados)
	for i in branches.size():
		if reveal < branch_t[i]:
			continue
		var local: float = clampf((reveal - branch_t[i]) / 0.25, 0.0, 1.0)
		_draw_poly(_slice(branches[i], local), a * 0.85, 0.5)

	# Cabeça do feixe durante a queda
	if reveal < 1.0 and shown.size() > 0:
		var head: Vector2 = shown[shown.size() - 1]
		_glow(head, 55.0, Color(COL_OUT, 0.55))
		_glow(head, 28.0, Color(COL_MID, 0.75))
		_glow(head, 10.0, Color(COL_CORE, 0.95))

	# Poeira luminosa ao longo do feixe
	for i in MOTE_COUNT:
		var flick_m := 0.5 + 0.5 * sin(mot_phase[i])
		var fl: float = flick_m * a
		_glow(mot_pos[i], mot_size[i] * 6.0, Color(COL_DEEP, fl * 0.35))
		_glow(mot_pos[i], mot_size[i] * 2.0, Color(COL_MID, fl * 0.7))

	# Brasas (sobem lentamente, esfriam)
	for i in EMBER_COUNT:
		var k: float = (t - STRIKE_TIME) / em_max[i]
		if k < 0.0 or k > 1.0:
			continue
		var ea: float = sin(k * PI)
		_glow(em_pos[i], em_size[i] * 1.6, Color(COL_DEEP, ea * 0.25))
		_glow(em_pos[i], em_size[i], Color(COL_MID, ea * 0.45))

	# Faíscas com trilha e cor que esfria (azul-claro → ciano → azul)
	for i in SPARK_COUNT:
		if t < sp_delay[i]:
			continue
		var k: float = sp_age[i] / sp_max[i]
		if k >= 1.0:
			continue
		var col: Color = COL_CORE.lerp(COL_MID, clampf(k * 2.0, 0.0, 1.0)).lerp(COL_OUT, clampf(k * 2.0 - 1.0, 0.0, 1.0))
		var sa: float = 1.0 - k
		var pos: Vector2 = sp_pos[i]
		var tail: Vector2 = pos - sp_vel[i] * 0.045
		draw_line(tail, pos, Color(col, sa * 0.35), sp_size[i] * 3.0)
		draw_line(tail, pos, Color(col, sa), sp_size[i])
		_glow(pos, 7.0 * sa + 2.0, Color(col, sa * 0.55))

	# Impacto: núcleo + 3 ondas de choque
	if t >= STRIKE_TIME * 0.8:
		var ik: float = clampf((t - STRIKE_TIME) / (DURATION - STRIKE_TIME), 0.0, 1.0)
		var ia: float = 1.0 - ik
		_glow(end_point, 80.0 * a + 12.0, Color(COL_DEEP, a * 0.45))
		_glow(end_point, 50.0 * a + 8.0, Color(COL_MID, a * 0.75))
		_glow(end_point, 18.0 * a + 4.0, Color(COL_CORE, a))
		var r1: float = 80.0 * (1.0 - pow(1.0 - ik, 3.0))
		draw_arc(end_point, r1, 0.0, TAU, 40, Color(COL_OUT, ia * 0.6), 3.0 * ia + 0.5, true)
		draw_arc(end_point, r1 * 0.72, 0.0, TAU, 36, Color(COL_MID, ia * 0.8), 2.0 * ia + 0.5, true)
		draw_arc(end_point, r1 * 0.42, 0.0, TAU, 28, Color(COL_CORE, ia * 0.5), 1.2, true)


func _draw_poly(pts: PackedVector2Array, a: float, s: float):
	if pts.size() < 2:
		return
	# Halo em 4 camadas: quanto mais larga, mais "borrada"
	draw_polyline(pts, Color(COL_DEEP, a * 0.06), 34.0 * s, true)
	draw_polyline(pts, Color(COL_OUT,  a * 0.12), 18.0 * s, true)
	draw_polyline(pts, Color(COL_OUT,  a * 0.28), 9.0 * s, true)
	draw_polyline(pts, Color(COL_MID,  a * 0.9), 3.4 * s, true)
	draw_polyline(pts, Color(COL_CORE, a), 1.2 * s, true)
