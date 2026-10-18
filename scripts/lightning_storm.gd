extends Node2D

# ═══════════════ CONFIG ═══════════════
var radius := 170.0
var bolt_count := 2
var damage := 25
var hit_radius := 45.0

const ISO := 0.55
const WARN_TIME := 0.7
const STRIKE_GAP := 0.14
const FX_TIME := 0.35
const SKY_HEIGHT := 700.0
const BOLT_SEGS := 12
const BRANCH_SEGS := 5
const FLICKER_TIME := 0.05
const RING_POINTS := 40

const AMBIENT_COUNT := 20
const SPARKS_PER_HIT := 18 # impacto no chão (era 12)
const BOLT_SPARKS_BURST := 14 # ← novo: estouro ao cair
const BOLT_SPARKS_TICK := 4 # ← novo: chiado por flicker
const MAX_SPARKS := 256 # era 96 (mais folga pro fluxo)
const SPARK_STRIDE := 7

# ═══════════════ PALETA AZUL ELÉTRICA ═══════════════
const COL_CORE := Color(1.0, 1.0, 1.0)
const COL_MID := Color(0.40, 0.85, 1.0)
const COL_OUT := Color(0.15, 0.45, 1.0)
const COL_DEEP := Color(0.08, 0.25, 0.9)
const COL_SPARK := Color(0.70, 0.95, 1.0)
const STORM_AUDIO: AudioStream = preload("res://assets/audio/storm.wav")



static var glow_tex: GradientTexture2D

var t := 0.0
var life_total := 0.0
var flicker_timer := 0.0
var area_flash := 0.0

var s_pos := PackedVector2Array()
var s_time := PackedFloat32Array()
var s_fired := PackedByteArray()
var s_bolt: Array[PackedVector2Array] = []
var s_branches: Array = []
var ring_pts := PackedVector2Array()

var sparks := PackedFloat32Array() # pool sem alocações
var spark_count := 0
var ambient := PackedFloat32Array() # x,y,phase,speed,size,dist_ratio


func _ready():
	randomize()
	radius = maxf(radius, 1.0)
	bolt_count = maxi(bolt_count, 1)
	hit_radius = maxf(hit_radius, 1.0)
	damage = maxi(damage, 0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_get_glow()
	ring_pts.resize(RING_POINTS + 1)
	sparks.resize(MAX_SPARKS * SPARK_STRIDE)

	s_pos.resize(bolt_count)
	s_time.resize(bolt_count)
	s_fired.resize(bolt_count)
	s_bolt.resize(bolt_count)
	s_branches.resize(bolt_count)
	for i in bolt_count:
		var a: float = randf() * TAU
		var d: float = sqrt(randf()) * radius * 0.9
		s_pos[i] = Vector2(cos(a) * d, sin(a) * d * ISO)
		s_time[i] = WARN_TIME + i * STRIKE_GAP + randf_range(0.0, 0.06)
		s_fired[i] = 0
		s_bolt[i] = PackedVector2Array()
		s_branches[i] = []
	life_total = WARN_TIME + bolt_count * STRIKE_GAP + FX_TIME + 0.15

	ambient.resize(AMBIENT_COUNT * 6)
	for i in AMBIENT_COUNT:
		var ang := randf() * TAU
		var d := sqrt(randf()) * radius * 0.85
		var idx := i * 6
		ambient[idx] = cos(ang) * d
		ambient[idx + 1] = sin(ang) * d * ISO
		ambient[idx + 2] = randf() * TAU
		ambient[idx + 3] = randf_range(0.4, 1.2)
		ambient[idx + 4] = randf_range(1.2, 2.8)
		ambient[idx + 5] = d / (radius * 0.85 + 1.0)


# ═══════════════ HELPERS ═══════════════
static func _get_glow() -> GradientTexture2D:
	if glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1),
			Color(1, 1, 1, 0.55),
			Color(1, 1, 1, 0.18),
			Color(1, 1, 1, 0),
		])
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
	draw_texture_rect(glow_tex,
		Rect2(center.x - r, center.y - r * squash, r * 2.0, r * 2.0 * squash), false, col)

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
	var main := _make_bolt(start, ground, BOLT_SEGS, 22.0)
	s_bolt[i] = main

	# 2–3 ramificações saindo de pontos aleatórios do tronco
	var branches: Array = []
	var n_br: int = 2 + randi() % 2
	for b in n_br:
		var idx: int = randi_range(3, BOLT_SEGS - 3)
		var from: Vector2 = main[idx]
		var dir: Vector2 = (main[idx + 1] - main[idx]).normalized()
		var blen: float = randf_range(40.0, 100.0)
		var bdir: Vector2 = dir.rotated(randf_range(-1.0, 1.0)).normalized()
		branches.append(_make_bolt(from, from + bdir * blen, BRANCH_SEGS, blen * 0.22))
	s_branches[i] = branches

func _spawn_bolt_sparks(pts: PackedVector2Array, count: int, size_mult := 1.0):
	if pts.size() < 2:
		return
	var stride := SPARK_STRIDE
	for n in count:
		if spark_count >= MAX_SPARKS:
			return
		# ponto aleatório ao longo do ziguezague
		var seg_idx: int = randi_range(0, pts.size() - 2)
		var seg_t: float = randf()
		var p: Vector2 = pts[seg_idx].lerp(pts[seg_idx + 1], seg_t)
		var seg_dir: Vector2 = (pts[seg_idx + 1] - pts[seg_idx]).normalized()
		var normal: Vector2 = seg_dir.orthogonal()
		# cospe pra fora do fio (perpendicular) + um pouco ao longo
		var side: float = -1.0 if randf() < 0.5 else 1.0
		var spd: float = randf_range(40.0, 150.0)
		var dir: Vector2 = (normal * side + seg_dir * randf_range(-0.5, 0.5)).normalized()
		var idx := spark_count * stride
		sparks[idx] = p.x
		sparks[idx + 1] = p.y
		sparks[idx + 2] = dir.x * spd
		sparks[idx + 3] = dir.y * spd * ISO
		sparks[idx + 4] = 0.0
		sparks[idx + 5] = randf_range(0.15, 0.35) # vida curta
		sparks[idx + 6] = randf_range(1.0, 2.5) * size_mult
		spark_count += 1

func _spawn_sparks(pos: Vector2, count: int):
	var stride := SPARK_STRIDE
	for n in count:
		if spark_count >= MAX_SPARKS:
			return
		var idx := spark_count * stride
		var ang := randf() * TAU
		var spd := randf_range(70.0, 240.0)
		sparks[idx] = pos.x
		sparks[idx + 1] = pos.y
		sparks[idx + 2] = cos(ang) * spd
		sparks[idx + 3] = sin(ang) * spd * ISO
		sparks[idx + 4] = 0.0
		sparks[idx + 5] = randf_range(0.25, 0.55)
		sparks[idx + 6] = randf_range(1.2, 3.0)
		spark_count += 1

func _apply_damage(i: int):
	var center: Vector2 = to_global(s_pos[i])
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D):
			continue
		var d: Vector2 = e.global_position - center
		if d.x * d.x + (d.y / ISO) * (d.y / ISO) <= hit_radius * hit_radius:
			if e.has_method("take_damage"):
				e.take_damage(damage)

func _play_strike_sound():
	var player := AudioStreamPlayer.new()
	player.stream = STORM_AUDIO
	get_tree().current_scene.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


# ═══════════════ UPDATE ═══════════════
func _process(delta: float):
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
			_play_strike_sound()
			_apply_damage(i)
			_spawn_sparks(s_pos[i], SPARKS_PER_HIT)
			_spawn_bolt_sparks(s_bolt[i], BOLT_SPARKS_BURST, 1.3) # ← novo
			area_flash = 1.0
		elif s_fired[i] == 1 and do_flicker and t - s_time[i] < FX_TIME:
			_regen_bolt(i)
			_spawn_bolt_sparks(s_bolt[i], BOLT_SPARKS_TICK, 0.9) # ← novo


	if area_flash > 0.0:
		area_flash = maxf(area_flash - delta * 3.5, 0.0)

	# Faíscas — swap-remove, sem alocar nada
	var drag := 1.0 - minf(delta * 4.0, 0.9)
	var i2 := 0
	while i2 < spark_count:
		var idx := i2 * SPARK_STRIDE
		var age := sparks[idx + 4] + delta
		if age >= sparks[idx + 5]:
			spark_count -= 1
			if i2 != spark_count:
				var last := spark_count * SPARK_STRIDE
				for k in SPARK_STRIDE:
					sparks[idx + k] = sparks[last + k]
			continue
		sparks[idx + 4] = age
		sparks[idx] += sparks[idx + 2] * delta
		sparks[idx + 1] += sparks[idx + 3] * delta
		sparks[idx + 2] *= drag
		sparks[idx + 3] *= drag
		i2 += 1

	queue_redraw()
	if t >= life_total:
		queue_free()


# ═══════════════ DRAW ═══════════════
func _draw():
	var fade_duration: float = maxf(life_total - WARN_TIME, 0.001)
	var fade: float = 1.0 - clampf((t - WARN_TIME) / fade_duration, 0.0, 1.0)
	fade = clampf(fade * 1.5, 0.0, 1.0)

	_draw_ambient(fade)
	_draw_area(fade)

	for i in bolt_count:
		if s_fired[i] == 0:
			_draw_marker(i)
		else:
			var age: float = t - s_time[i]
			if age < FX_TIME:
				_draw_strike(i, age)

	_draw_sparks()


func _draw_ambient(fade: float):
	if fade <= 0.01:
		return
	var warn: float = clampf(t / WARN_TIME, 0.0, 1.0)
	for i in AMBIENT_COUNT:
		var idx := i * 6
		var phase := ambient[idx + 2]
		var speed := ambient[idx + 3]
		var size := ambient[idx + 4]
		var wave := sin(t * 2.0 * speed + phase)
		var px := ambient[idx] + wave * 4.0
		var py := ambient[idx + 1] - wave * 6.0
		var a: float = fade * warn * (0.35 + 0.35 * sin(t * 5.0 * speed + phase))
		if a < 0.01:
			continue
		_glow(Vector2(px, py), size * 2.5, Color(COL_MID, a * 0.4), ISO)


func _draw_area(fade: float):
	var warn: float = clampf(t / WARN_TIME, 0.0, 1.0)
	var pulse: float = 0.75 + 0.25 * sin(t * 18.0)
	var a: float = fade * (0.35 + 0.65 * warn) * pulse

	# Glow triplo — azul profundo → azul médio
	_glow(Vector2.ZERO, radius * 1.4, Color(COL_DEEP, a * 0.35), ISO)
	_glow(Vector2.ZERO, radius * 1.0, Color(COL_OUT, a * 0.40), ISO)
	_glow(Vector2.ZERO, radius * 0.65, Color(COL_MID, a * 0.30), ISO)

	# Flash global quando cai um raio
	if area_flash > 0.0:
		_glow(Vector2.ZERO, radius * 1.6, Color(COL_MID, area_flash * 0.40), ISO)
		_glow(Vector2.ZERO, radius * 0.9, Color(COL_CORE, area_flash * 0.30), ISO)

	# Anel serrilhado girando
	for i in RING_POINTS + 1:
		var k: int = i % RING_POINTS
		var ang: float = TAU * k / RING_POINTS + t * 0.8
		var wob: float = 1.0 + (0.025 if k % 2 == 0 else -0.025)
		ring_pts[i] = Vector2(cos(ang), sin(ang) * ISO) * radius * wob
	draw_polyline(ring_pts, Color(COL_OUT, a * 0.5), 5.0)
	draw_polyline(ring_pts, Color(COL_MID, a * 0.9), 1.6, true)


func _draw_marker(i: int):
	var p: Vector2 = s_pos[i]
	var k: float = clampf(t / s_time[i], 0.0, 1.0)
	var r: float = lerpf(hit_radius * 1.5, hit_radius * 0.5, k)
	var a: float = 0.3 + 0.7 * k
	var pulse: float = 0.7 + 0.3 * sin(t * 22.0 + float(i))

	_glow(p, hit_radius * 1.3, Color(COL_MID, a * 0.25 * pulse), ISO)
	draw_set_transform(p, 0.0, Vector2(1.0, ISO))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(COL_MID, a), 1.8, true)
	draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 18, Color(COL_CORE, a * pulse), 1.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_strike(i: int, age: float):
	var a: float = pow(1.0 - age / FX_TIME, 0.7)
	var flicker: float = 0.85 + 0.15 * sin(age * 90.0)
	var p: Vector2 = s_pos[i]
	var pts: PackedVector2Array = s_bolt[i]

	# Glow atmosférico expandindo
	_glow(p, hit_radius * 2.5 * a, Color(COL_DEEP, a * 0.40), ISO)
	_glow(p, hit_radius * 1.6 * a, Color(COL_OUT, a * 0.50), ISO)

	# Raio: halo → corpo → núcleo
	var halo_a: float = a * 0.35 * flicker
	var body_a: float = a * 0.90 * flicker
	draw_polyline(pts, Color(COL_OUT, halo_a), 9.0)
	draw_polyline(pts, Color(COL_MID, body_a), 3.0, true)
	draw_polyline(pts, Color(COL_CORE, a), 1.3, true)

	# Ramificações (mesma camada, mais finas)
	var branches: Array = s_branches[i]
	for br in branches:
		if br.size() < 2:
			continue
		draw_polyline(br, Color(COL_OUT, halo_a * 0.6), 4.0)
		draw_polyline(br, Color(COL_MID, body_a * 0.8), 1.8, true)
		draw_polyline(br, Color(COL_CORE, a * 0.7), 0.9, true)

	# Flash forte no impacto
	_glow(p, hit_radius * 2.0 * a, Color(COL_MID, a * 0.7), ISO)
	_glow(p, hit_radius * 0.9 * a, Color(COL_CORE, a), ISO)

	# Onda de choque dupla
	var k: float = age / FX_TIME
	draw_set_transform(p, 0.0, Vector2(1.0, ISO))
	draw_arc(Vector2.ZERO, hit_radius * (0.3 + k * 1.2), 0.0, TAU, 28,
		Color(COL_MID, a * 0.9), 2.4, true)
	draw_arc(Vector2.ZERO, hit_radius * (0.5 + k * 1.8), 0.0, TAU, 28,
		Color(COL_OUT, a * 0.4), 1.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sparks():
	if spark_count == 0:
		return
	for i in spark_count:
		var idx := i * SPARK_STRIDE
		var age := sparks[idx + 4]
		var life := 1.0 - age / sparks[idx + 5]
		if life <= 0.0:
			continue
		var px := sparks[idx]
		var py := sparks[idx + 1]
		var vx := sparks[idx + 2]
		var vy := sparks[idx + 3]
		var sz := sparks[idx + 6]
		# Trail curto = faísca elétrica
		draw_line(
			Vector2(px, py),
			Vector2(px - vx * 0.02, py - vy * 0.02),
			Color(COL_SPARK, life),
			sz * 0.6, true
		)
