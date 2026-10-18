extends Node2D

var radius := 200.0
var progress := 0.0

const DURATION := 0.75
const ISO := 0.55
const BOLT_COUNT := 12
const BOLT_SEGS := 18
const BRANCH_SEGS := 6
const BRANCH_PER_BOLT := 3
const SPARK_COUNT := 90
const DUST_COUNT := 50
const GRAVITY := 900.0
const FLICKER_TIME := 0.05
const RING_POINTS := 64

const COL_CORE := Color(0.65, 0.92, 1.0)   # azul claro (núcleo)
const COL_MID  := Color(0.28, 0.65, 1.0)   # azul elétrico
const COL_OUT  := Color(0.10, 0.32, 0.95)  # azul profundo
const COL_DEEP := Color(0.04, 0.10, 0.55)  # azul muito profundo (blur)

static var glow_tex: GradientTexture2D

var bolts := []
var flicker_timer := 0.0

var sp_pos := PackedVector2Array()
var sp_vel := PackedVector2Array()
var sp_z := PackedFloat32Array()
var sp_vz := PackedFloat32Array()
var sp_size := PackedFloat32Array()
var sp_phase := PackedFloat32Array()

var dust_pos := PackedVector2Array()
var dust_vel := PackedVector2Array()
var dust_phase := PackedFloat32Array()
var dust_size := PackedFloat32Array()

var ring_noise := PackedFloat32Array()
var ring_pts := PackedVector2Array()
var ring2_pts := PackedVector2Array()
var ring3_pts := PackedVector2Array()


func _ready():
	randomize()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

	_get_glow()
	ring_pts.resize(RING_POINTS + 1)
	ring2_pts.resize(RING_POINTS + 1)
	ring3_pts.resize(RING_POINTS + 1)
	ring_noise.resize(RING_POINTS)

	for i in BOLT_COUNT:
		var ang := TAU * i / BOLT_COUNT + randf_range(-0.25, 0.25)
		bolts.append({
			"ang": ang,
			"front": sin(ang) >= 0.0,
			"lenf": randf_range(0.55, 1.2),
			"arc": randf_range(0.0, 60.0),
			"pts": PackedVector2Array(),
			"branches": [],
			"tip": Vector2.ZERO,
		})

	sp_pos.resize(SPARK_COUNT)
	sp_vel.resize(SPARK_COUNT)
	sp_z.resize(SPARK_COUNT)
	sp_vz.resize(SPARK_COUNT)
	sp_size.resize(SPARK_COUNT)
	sp_phase.resize(SPARK_COUNT)
	for i in SPARK_COUNT:
		sp_pos[i] = Vector2.ZERO
		sp_vel[i] = Vector2.from_angle(randf() * TAU) * randf_range(150.0, 550.0)
		sp_z[i] = randf_range(2.0, 30.0)
		sp_vz[i] = randf_range(180.0, 520.0)
		sp_size[i] = randf_range(0.6, 2.2)
		sp_phase[i] = randf() * TAU

	dust_pos.resize(DUST_COUNT)
	dust_vel.resize(DUST_COUNT)
	dust_phase.resize(DUST_COUNT)
	dust_size.resize(DUST_COUNT)
	for i in DUST_COUNT:
		var a := randf() * TAU
		var rr := randf_range(0.35, 1.2) * radius
		dust_pos[i] = Vector2(cos(a), sin(a)) * rr
		dust_vel[i] = Vector2.from_angle(a + PI * 0.5) * randf_range(8, 25)
		dust_phase[i] = randf() * TAU
		dust_size[i] = randf_range(0.5, 2.0)

	_regen()


# ---------- helpers ----------
static func _get_glow() -> GradientTexture2D:
	if glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 0.65, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1.0),
			Color(1, 1, 1, 0.6),
			Color(1, 1, 1, 0.22),
			Color(1, 1, 1, 0.05),
			Color(1, 1, 1, 0.0),
		])
		glow_tex = GradientTexture2D.new()
		glow_tex.gradient = g
		glow_tex.fill = GradientTexture2D.FILL_RADIAL
		glow_tex.fill_from = Vector2(0.5, 0.5)
		glow_tex.fill_to = Vector2(1.0, 0.5)
		glow_tex.width = 256
		glow_tex.height = 256
	return glow_tex


func _glow(center: Vector2, r: float, col: Color, squash := 1.0):
	if r <= 0.5 or col.a <= 0.01:
		return
	draw_texture_rect(glow_tex, Rect2(center.x - r, center.y - r * squash, r * 2.0, r * 2.0 * squash), false, col)


func proj(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y * ISO - p.z)


# ---------- geração ----------
func _bolt3(start: Vector3, ang: float, len: float, segs: int, jitter: float, arc: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.resize(segs + 1)
	var d := Vector2.from_angle(ang)
	var n := d.orthogonal()
	for i in segs + 1:
		var t := float(i) / segs
		var env := sin(t * PI)
		var b := Vector2(start.x, start.y) + d * len * t + n * randf_range(-1.0, 1.0) * jitter * env
		pts[i] = Vector3(b.x, b.y, start.z + 6.0 + arc * env + randf_range(0.0, 4.0) * env)
	return pts


func _to2d(p3: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(p3.size())
	for i in p3.size():
		out[i] = proj(p3[i])
	return out


func _regen():
	var e: float = 1.0 - pow(1.0 - progress, 3.0)
	for b in bolts:
		var L: float = radius * clampf(e * 1.3, 0.05, 1.0) * float(b.lenf)
		var ang: float = b.ang
		var p3: PackedVector3Array = _bolt3(Vector3.ZERO, ang, L, BOLT_SEGS, 16.0, float(b.arc))
		var p2: PackedVector2Array = _to2d(p3)
		b.pts = p2
		b.tip = p2[p2.size() - 1]
		b.branches = []
		for k in BRANCH_PER_BOLT:
			var idx: int = randi_range(3, BOLT_SEGS - 3)
			var br: PackedVector3Array = _bolt3(p3[idx], ang + randf_range(-1.0, 1.0), L * 0.35, BRANCH_SEGS, 9.0, 0.0)
			b.branches.append(_to2d(br))
	for i in RING_POINTS:
		ring_noise[i] = randf_range(-0.07, 0.07)


# ---------- update ----------
func _process(delta):
	progress += delta / DURATION

	flicker_timer += delta
	if flicker_timer >= FLICKER_TIME:
		flicker_timer = 0.0
		_regen()

	for i in SPARK_COUNT:
		sp_pos[i] += sp_vel[i] * delta
		sp_z[i] += sp_vz[i] * delta
		sp_vz[i] -= GRAVITY * delta
		sp_phase[i] += delta * 14.0
		if sp_z[i] < 0.0:
			sp_z[i] = 0.0
			sp_vz[i] = -sp_vz[i] * 0.4
			sp_vel[i] *= 0.6

	for i in DUST_COUNT:
		var a := dust_phase[i]
		var perp := Vector2(-dust_vel[i].y, dust_vel[i].x).normalized()
		dust_pos[i] += (dust_vel[i] + perp * sin(a) * 18.0) * delta
		dust_phase[i] += delta * 1.8
		if dust_pos[i].length() > radius * 1.4:
			var na := randf() * TAU
			var rr := randf_range(0.3, 0.8) * radius
			dust_pos[i] = Vector2(cos(na), sin(na)) * rr

	queue_redraw()
	if progress >= 1.0:
		queue_free()


# ---------- desenho ----------
func _draw():
	var e := 1.0 - pow(1.0 - progress, 3.0)
	var alpha := 1.0 - progress
	var r := radius * e

	_draw_ground(r, alpha)
	_draw_dust(alpha)
	_draw_sparks(false, alpha)
	_draw_bolts(false, alpha)
	_draw_pillar(e, alpha)
	_draw_bolts(true, alpha)
	_draw_sparks(true, alpha)
	_draw_flash()


func _draw_ground(r: float, alpha: float):
	# blur de luz no chão em 4 camadas
	_glow(Vector2.ZERO, r * 1.7, Color(COL_DEEP, alpha * 0.5), ISO)
	_glow(Vector2.ZERO, r * 1.25, Color(COL_OUT, alpha * 0.55), ISO)
	_glow(Vector2.ZERO, r * 0.85, Color(COL_MID, alpha * 0.5), ISO)
	_glow(Vector2.ZERO, r * 0.4, Color(COL_CORE, alpha * 0.6), ISO)

	for i in RING_POINTS + 1:
		var k := i % RING_POINTS
		var a := TAU * k / RING_POINTS
		var rr := r * (1.0 + ring_noise[k])
		ring_pts[i] = Vector2(cos(a) * rr, sin(a) * rr * ISO - 6.0)
		var rr2 := rr * 0.72
		ring2_pts[i] = Vector2(cos(a) * rr2, sin(a) * rr2 * ISO - 4.0)
		var rr3 := rr * 0.42
		ring3_pts[i] = Vector2(cos(a) * rr3, sin(a) * rr3 * ISO - 2.0)

	var w := lerpf(5.0, 1.0, progress)
	draw_polyline(ring_pts, Color(COL_DEEP, alpha * 0.5), w * 4.0)
	draw_polyline(ring_pts, Color(COL_OUT, alpha * 0.7), w * 2.0)
	draw_polyline(ring_pts, Color(COL_MID, alpha), w)
	draw_polyline(ring_pts, Color(COL_CORE, alpha), w * 0.4, true)
	draw_polyline(ring2_pts, Color(COL_MID, alpha * 0.55), 1.6)
	draw_polyline(ring3_pts, Color(COL_MID, alpha * 0.28), 1.0)


func _draw_pillar(e: float, alpha: float):
	var h := radius * 1.3 * clampf(e * 1.4, 0.0, 1.0)
	var rw := radius * 0.32 * (1.0 + progress * 0.5)

	# coluna difusa (blur vertical em 2 camadas) + base
	_glow(Vector2(0, -h * 0.5), rw * 1.8, Color(COL_DEEP, alpha * 0.5), h / (rw * 1.8) * 0.5 + 0.3)
	_glow(Vector2(0, -h * 0.5), rw * 1.15, Color(COL_OUT, alpha * 0.6), h / (rw * 1.15) * 0.5 + 0.2)
	_glow(Vector2.ZERO, rw * 1.3, Color(COL_MID, alpha * 0.6), ISO)
	_glow(Vector2.ZERO, rw * 0.6, Color(COL_CORE, alpha * 0.75), ISO)

	# feixe central em 4 camadas (blur)
	var top := proj(Vector3(0, 0, h * 1.3))
	var w := 10.0 * alpha
	draw_line(Vector2.ZERO, top, Color(COL_DEEP, alpha * 0.3), w * 3.0)
	draw_line(Vector2.ZERO, top, Color(COL_OUT, alpha * 0.55), w * 1.5)
	draw_line(Vector2.ZERO, top, Color(COL_MID, alpha * 0.85), w * 0.6)
	draw_line(Vector2.ZERO, top, Color(COL_CORE, alpha), w * 0.2, true)


func _draw_bolts(front: bool, alpha: float):
	var a := pow(alpha, 0.7)
	for b in bolts:
		if b.front != front:
			continue
		_draw_poly(b.pts, a, 1.0)
		for br in b.branches:
			_draw_poly(br, a * 0.75, 0.55)
		# brilho na ponta (glow bem grande)
		_glow(b.tip, 34.0 * a, Color(COL_DEEP, a * 0.55))
		_glow(b.tip, 18.0 * a, Color(COL_MID, a * 0.8))
		_glow(b.tip, 6.0 * a, Color(COL_CORE, a))


func _draw_poly(pts: PackedVector2Array, a: float, s: float):
	draw_polyline(pts, Color(COL_DEEP, a * 0.18), 14.0 * s)
	draw_polyline(pts, Color(COL_OUT, a * 0.35), 7.0 * s)
	draw_polyline(pts, Color(COL_MID, a * 0.85), 2.6 * s, true)
	draw_polyline(pts, Color(COL_CORE, a), 1.0 * s, true)


func _draw_sparks(front: bool, alpha: float):
	for i in SPARK_COUNT:
		var p := sp_pos[i]
		if (p.y >= 0.0) != front:
			continue
		var z := sp_z[i]
		var head := proj(Vector3(p.x, p.y, z))
		var tail := proj(Vector3(p.x - sp_vel[i].x * 0.035, p.y - sp_vel[i].y * 0.035, z - sp_vz[i] * 0.035))
		var flicker := 0.7 + 0.3 * sin(sp_phase[i])
		var sz := sp_size[i]
		# trilha
		draw_line(tail, head, Color(COL_OUT, alpha * 0.6 * flicker), sz * 2.4)
		draw_line(tail, head, Color(COL_MID, alpha * 0.9 * flicker), sz * 1.2)
		draw_line(tail, head, Color(COL_CORE, alpha * flicker), sz * 0.5)
		# glow na cabeça (só faíscas maiores)
		if sz > 1.0:
			_glow(head, sz * 7.0, Color(COL_DEEP, alpha * 0.4 * flicker))
			_glow(head, sz * 3.0, Color(COL_MID, alpha * 0.65 * flicker))
			_glow(head, sz * 1.4, Color(COL_CORE, alpha * 0.9 * flicker))


func _draw_dust(alpha: float):
	var a := alpha * 0.6
	for i in DUST_COUNT:
		var p := dust_pos[i]
		var wob := sin(dust_phase[i]) * 12.0
		var sp := Vector2(p.x, p.y * ISO - 18.0 - wob)
		var fl := 0.6 + 0.4 * sin(dust_phase[i] * 1.7)
		_glow(sp, dust_size[i] * 7.0, Color(COL_OUT, a * 0.4 * fl))
		_glow(sp, dust_size[i] * 2.8, Color(COL_MID, a * fl))


func _draw_flash():
	if progress > 0.3:
		return
	var f := 1.0 - progress / 0.3
	var c := Vector2(0, -30)
	_glow(c, radius * 1.2 * f, Color(COL_DEEP, f * 0.55))
	_glow(c, radius * 0.7 * f, Color(COL_MID, f * 0.8))
	_glow(c, radius * 0.3 * f, Color(COL_CORE, f))
