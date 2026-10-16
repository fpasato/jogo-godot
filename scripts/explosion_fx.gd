extends Node2D

var radius := 200.0
var progress := 0.0

const DURATION := 0.6
const ISO := 0.55
const BOLT_COUNT := 9
const BOLT_SEGS := 12
const BRANCH_SEGS := 5
const SPARK_COUNT := 28
const GRAVITY := 900.0
const FLICKER_TIME := 0.06
const RING_POINTS := 40

const COL_CORE := Color(1, 1, 1)
const COL_MID := Color(0.45, 0.85, 1)
const COL_OUT := Color(0.4, 0.3, 1)

static var glow_tex: GradientTexture2D   # textura de brilho compartilhada

var bolts := []
var flicker_timer := 0.0

# faíscas em arrays paralelos (mais rápido que dicionários)
var sp_pos := PackedVector2Array()
var sp_vel := PackedVector2Array()
var sp_z := PackedFloat32Array()
var sp_vz := PackedFloat32Array()
var sp_size := PackedFloat32Array()

var ring_noise := PackedFloat32Array()
var ring_pts := PackedVector2Array()
var ring2_pts := PackedVector2Array()


func _ready():
	randomize()
	# Blend aditivo: o brilho acende o que está atrás
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

	_get_glow()
	ring_pts.resize(RING_POINTS + 1)
	ring2_pts.resize(RING_POINTS + 1)
	ring_noise.resize(RING_POINTS)

	for i in BOLT_COUNT:
		var ang := TAU * i / BOLT_COUNT + randf_range(-0.2, 0.2)
		bolts.append({
			"ang": ang,
			"front": sin(ang) >= 0.0,
			"lenf": randf_range(0.6, 1.15),
			"arc": randf_range(0.0, 50.0),
			"pts": PackedVector2Array(),
			"branches": [],
			"tip": Vector2.ZERO,
		})

	sp_pos.resize(SPARK_COUNT)
	sp_vel.resize(SPARK_COUNT)
	sp_z.resize(SPARK_COUNT)
	sp_vz.resize(SPARK_COUNT)
	sp_size.resize(SPARK_COUNT)
	for i in SPARK_COUNT:
		sp_pos[i] = Vector2.ZERO
		sp_vel[i] = Vector2.from_angle(randf() * TAU) * randf_range(120.0, 400.0)
		sp_z[i] = randf_range(5.0, 30.0)
		sp_vz[i] = randf_range(150.0, 420.0)
		sp_size[i] = randf_range(0.8, 1.8)

	_regen()


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

# Brilho suave com UMA chamada de desenho (squash < 1 achata no chão)
func _glow(center: Vector2, r: float, col: Color, squash := 1.0):
	if r <= 0.5 or col.a <= 0.01:
		return
	draw_texture_rect(glow_tex, Rect2(center.x - r, center.y - r * squash, r * 2.0, r * 2.0 * squash), false, col)

func proj(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y * ISO - p.z)


# ---------- geração (só roda a cada FLICKER_TIME) ----------
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
		var p3: PackedVector3Array = _bolt3(Vector3.ZERO, ang, L, BOLT_SEGS, 14.0, float(b.arc))
		var p2: PackedVector2Array = _to2d(p3)
		b.pts = p2
		b.tip = p2[p2.size() - 1]
		b.branches = []
		for k in 2:
			var idx: int = randi_range(3, BOLT_SEGS - 3)
			var br: PackedVector3Array = _bolt3(p3[idx], ang + randf_range(-0.9, 0.9), L * 0.3, BRANCH_SEGS, 8.0, 0.0)
			b.branches.append(_to2d(br))
	for i in RING_POINTS:
		ring_noise[i] = randf_range(-0.06, 0.06)

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
		if sp_z[i] < 0.0:
			sp_z[i] = 0.0
			sp_vz[i] = -sp_vz[i] * 0.4
			sp_vel[i] *= 0.6

	queue_redraw()
	if progress >= 1.0:
		queue_free()


# ---------- desenho ----------
func _draw():
	var e := 1.0 - pow(1.0 - progress, 3.0)
	var alpha := 1.0 - progress
	var r := radius * e

	_draw_ground(r, alpha)
	_draw_sparks(false, alpha)    # atrás
	_draw_bolts(false, alpha)
	_draw_pillar(e, alpha)
	_draw_bolts(true, alpha)      # na frente
	_draw_sparks(true, alpha)
	_draw_flash()

func _draw_ground(r: float, alpha: float):
	# luz no chão: 3 brilhos suaves em vez de várias elipses
	_glow(Vector2.ZERO, r * 1.25, Color(COL_OUT, alpha * 0.45), ISO)
	_glow(Vector2.ZERO, r * 0.8, Color(COL_MID, alpha * 0.4), ISO)
	_glow(Vector2.ZERO, r * 0.35, Color(COL_CORE, alpha * 0.5), ISO)

	# anel de choque fino e serrilhado (arrays reaproveitados, sem alocar)
	for i in RING_POINTS + 1:
		var k := i % RING_POINTS
		var a := TAU * k / RING_POINTS
		var rr := r * (1.0 + ring_noise[k])
		ring_pts[i] = Vector2(cos(a) * rr, sin(a) * rr * ISO - 6.0)
		var rr2 := rr * 0.65
		ring2_pts[i] = Vector2(cos(a) * rr2, sin(a) * rr2 * ISO - 3.0)

	var w := lerpf(4.0, 1.0, progress)
	draw_polyline(ring_pts, Color(COL_OUT, alpha * 0.35), w * 3.0)
	draw_polyline(ring_pts, Color(COL_MID, alpha * 0.9), w)
	draw_polyline(ring_pts, Color(COL_CORE, alpha), w * 0.4, true)
	draw_polyline(ring2_pts, Color(COL_MID, alpha * 0.4), 1.2)

func _draw_pillar(e: float, alpha: float):
	var h := radius * 1.1 * clampf(e * 1.4, 0.0, 1.0)
	var rw := radius * 0.3 * (1.0 + progress * 0.4)

	# coluna de luz: glow esticado na vertical + base
	_glow(Vector2(0, -h * 0.5), rw, Color(COL_OUT, alpha * 0.5), h / rw * 0.5 + 0.2)
	_glow(Vector2.ZERO, rw * 1.1, Color(COL_MID, alpha * 0.5), ISO)

	# feixe central fino
	var top := proj(Vector3(0, 0, h * 1.2))
	var w := 8.0 * alpha
	draw_line(Vector2.ZERO, top, Color(COL_MID, alpha * 0.5), w)
	draw_line(Vector2.ZERO, top, Color(COL_CORE, alpha), w * 0.25, true)

func _draw_bolts(front: bool, alpha: float):
	var a := pow(alpha, 0.7)
	for b in bolts:
		if b.front != front:
			continue
		_draw_poly(b.pts, a, 1.0)
		for br in b.branches:
			_draw_poly(br, a, 0.55)
		# brilho na ponta
		_glow(b.tip, 16.0 * a, Color(COL_MID, a * 0.7))
		_glow(b.tip, 5.0 * a, Color(COL_CORE, a))

func _draw_poly(pts: PackedVector2Array, a: float, s: float):
	draw_polyline(pts, Color(COL_OUT, a * 0.30), 6.0 * s)             # halo
	draw_polyline(pts, Color(COL_MID, a * 0.85), 2.4 * s, true)       # corpo
	draw_polyline(pts, Color(COL_CORE, a), 1.0 * s, true)             # núcleo fino

func _draw_sparks(front: bool, alpha: float):
	for i in SPARK_COUNT:
		var p := sp_pos[i]
		if (p.y >= 0.0) != front:
			continue
		var z := sp_z[i]
		var head := proj(Vector3(p.x, p.y, z))
		var tail := proj(Vector3(p.x - sp_vel[i].x * 0.03, p.y - sp_vel[i].y * 0.03, z - sp_vz[i] * 0.03))
		draw_line(tail, head, Color(COL_MID, alpha), sp_size[i] * 1.6)
		draw_line(tail, head, Color(COL_CORE, alpha), sp_size[i] * 0.7)

func _draw_flash():
	if progress > 0.25:
		return
	var f := 1.0 - progress / 0.25
	var c := Vector2(0, -20)
	_glow(c, radius * 0.6 * f, Color(COL_MID, f * 0.8))
	_glow(c, radius * 0.22 * f, Color(COL_CORE, f))
