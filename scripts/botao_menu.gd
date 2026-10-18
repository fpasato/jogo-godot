class_name BotaoMenu
extends Button

# ═══════════ TEMA ═══════════
const COR_FUNDO_NORMAL  := Color("#021F59")
const COR_FUNDO_HOVER   := Color("#0554F2")
const COR_FUNDO_PRESSED := Color("#021226")
const COR_BORDA         := Color("#056CF2")
const COR_BORDA_HOVER   := Color("#7DCBFF")
const COR_TEXTO         := Color("#E8F4FF")
const COR_TEXTO_HOVER   := Color.WHITE
const COR_GLOW          := Color("#5BB8FF")
const COR_ACCENT        := Color("#7DCBFF")

const COR_RAIO_CORE := Color(1.0, 1.0, 1.0)
const COR_RAIO_MID  := Color("#9DDCFF")
const COR_RAIO_OUT  := Color("#056CF2")
const COR_SPARK     := Color("#BFE9FF")

const TAMANHO_FONTE := 26
const DESLOCAMENTO_HOVER := 18.0
const ESCALA_HOVER := 1.06

const AUDIO_HOVER: AudioStream = preload("res://assets/audio/hover.mp3")
const CHAMFER := 10.0

# ═══════════ ELETRICIDADE NA BORDA ═══════════
const QTD_ARCOS := 6              # quantos arcos ao mesmo tempo
const ARCO_MIN := 25.0            # comprimento mínimo do arco (px)
const ARCO_MAX := 80.0            # comprimento máximo do arco (px)
const PASSO_ARCO := 7.0           # distância entre pontos do arco
const TREMOR := 3.0               # quanto o raio "balança" para os lados
const FLICKER_TIME := 0.045       # a cada quanto tempo os arcos mudam
const FADE_SPEED := 7.0

# Faíscas (pequenas, ficam perto da borda)
const SPARK_STRIDE := 7           # x,y,vx,vy,age,max_age,size
const MAX_SPARKS := 120
const SPARK_CHANCE := 0.35
const SPARK_SPEED_MIN := 10.0
const SPARK_SPEED_MAX := 40.0

static var _glow_tex: GradientTexture2D

var _tween: Tween
var _mouse_inside := false
var _has_focus := false
var _hover := false
var _intensidade := 0.0
var _flicker := 0.0
var _arcos: Array = []
var _audio_player: AudioStreamPlayer
var _painter: Control
var _bolts: Control

# Contorno do botão (usado para a eletricidade seguir a borda)
var _perim_pts := PackedVector2Array()
var _perim_cum := PackedFloat32Array()
var _perim_total := 0.0

var _sparks := PackedFloat32Array()
var _spark_count := 0


class PaintLayer extends Control:
	var _btn
	func _draw() -> void:
		if _btn:
			_btn._paint(self)

class BoltLayer extends Control:
	var _btn
	func _draw() -> void:
		if _btn:
			_btn._render_bolts(self)


func _ready() -> void:
	custom_minimum_size = Vector2(320, 64)
	clip_contents = false

	add_theme_font_size_override("font_size", TAMANHO_FONTE)
	add_theme_color_override("font_color", COR_TEXTO)
	add_theme_color_override("font_hover_color", COR_TEXTO_HOVER)
	add_theme_color_override("font_focus_color", COR_TEXTO_HOVER)
	add_theme_color_override("font_pressed_color", Color.WHITE)

	var vazio := StyleBoxEmpty.new()
	vazio.content_margin_left = 28
	vazio.content_margin_right = 28
	vazio.content_margin_top = 12
	vazio.content_margin_bottom = 12
	for est in ["normal", "hover", "focus", "pressed", "disabled"]:
		add_theme_stylebox_override(est, vazio)

	_get_glow_tex()
	pivot_offset = size / 2.0
	resized.connect(func():
		pivot_offset = size / 2.0
		_calcular_perimetro()
	)
	_calcular_perimetro()

	_sparks.resize(MAX_SPARKS * SPARK_STRIDE)

	_painter = PaintLayer.new()
	_painter._btn = self
	_painter.show_behind_parent = true
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_painter)
	_painter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_bolts = BoltLayer.new()
	_bolts._btn = self
	_bolts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bolts)
	_bolts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = AUDIO_HOVER
	_audio_player.volume_db = -6.0
	add_child(_audio_player)

	mouse_entered.connect(func(): _mouse_inside = true;  _atualizar())
	mouse_exited.connect( func(): _mouse_inside = false; _atualizar())
	focus_entered.connect(func(): _has_focus = true;     _painter.queue_redraw())
	focus_exited.connect( func(): _has_focus = false;    _painter.queue_redraw())
	button_down.connect(_painter.queue_redraw)
	button_up.connect(_painter.queue_redraw)


func _atualizar() -> void:
	if _mouse_inside == _hover:
		_painter.queue_redraw()
		return
	_hover = _mouse_inside
	if _hover:
		_animar(Vector2(ESCALA_HOVER, ESCALA_HOVER), DESLOCAMENTO_HOVER)
		_flicker = 0.0
		_gerar_arcos()
		if _audio_player.stream and not _audio_player.playing:
			_audio_player.play()
	else:
		_animar(Vector2.ONE, 0.0)
	_painter.queue_redraw()
	_bolts.queue_redraw()


func _animar(escala_alvo: Vector2, deslocamento: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", escala_alvo, 0.18)
	_tween.tween_property(self, "position:x", deslocamento, 0.18)


func _process(delta: float) -> void:
	if _hover:
		_painter.queue_redraw()

	# Liga/desliga suavemente a eletricidade
	var alvo := 1.0 if _hover else 0.0
	_intensidade = move_toward(_intensidade, alvo, delta * FADE_SPEED)

	if _intensidade > 0.0:
		_flicker += delta
		if _flicker >= FLICKER_TIME:
			_flicker = 0.0
			if _hover:
				_gerar_arcos()
		_bolts.queue_redraw()
	elif not _arcos.is_empty():
		_arcos.clear()
		_bolts.queue_redraw()

	if _spark_count > 0:
		_atualizar_faiscas(delta)
		_bolts.queue_redraw()


# ═══════════ CONTORNO DO BOTÃO ═══════════
func _calcular_perimetro() -> void:
	var w := size.x
	var h := size.y
	var c := CHAMFER
	_perim_pts = PackedVector2Array([
		Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c),
	])
	_perim_cum = PackedFloat32Array()
	_perim_total = 0.0
	var n := _perim_pts.size()
	for i in n:
		_perim_cum.append(_perim_total)
		_perim_total += _perim_pts[i].distance_to(_perim_pts[(i + 1) % n])


# Retorna [posição, normal] de um ponto a uma distância d ao longo da borda
func _ponto_na_borda(d: float) -> Array:
	d = fposmod(d, _perim_total)
	var n := _perim_pts.size()
	var seg := n - 1
	for i in n:
		var fim := _perim_cum[i + 1] if i + 1 < n else _perim_total
		if d < fim:
			seg = i
			break
	var a := _perim_pts[seg]
	var b := _perim_pts[(seg + 1) % n]
	var tang := (b - a).normalized()
	var pos := a + tang * (d - _perim_cum[seg])
	return [pos, tang.orthogonal()]


# ═══════════ ARCOS ELÉTRICOS (colados na borda) ═══════════
func _gerar_arcos() -> void:
	_arcos.clear()
	if size.x < 4.0 or size.y < 4.0 or _perim_total <= 0.0:
		return

	for i in QTD_ARCOS:
		var inicio := randf() * _perim_total
		var comp := randf_range(ARCO_MIN, ARCO_MAX)
		var segs := maxi(int(comp / PASSO_ARCO), 3)
		var pts := PackedVector2Array()
		pts.resize(segs + 1)

		for s in segs + 1:
			var k := float(s) / segs
			var info := _ponto_na_borda(inicio + comp * k)
			var pos: Vector2 = info[0]
			var nrm: Vector2 = info[1]
			var env := sin(k * PI)  # pontas encostam na borda
			pts[s] = pos + nrm * randf_range(-1.0, 1.0) * TREMOR * env
		_arcos.append(pts)

		if randf() < SPARK_CHANCE:
			_spawn_faisca(pts)


# ═══════════ FAÍSCAS (pequenas e curtas) ═══════════
func _spawn_faisca(pts: PackedVector2Array) -> void:
	if _spark_count >= MAX_SPARKS or pts.size() < 2:
		return
	var idx_pt := randi_range(0, pts.size() - 2)
	var p := pts[idx_pt].lerp(pts[idx_pt + 1], randf())
	var seg_dir := (pts[idx_pt + 1] - pts[idx_pt]).normalized()
	var nrm := seg_dir.orthogonal()
	var lado := -1.0 if randf() < 0.5 else 1.0
	var v := (nrm * lado + seg_dir * randf_range(-0.6, 0.6)).normalized() \
		* randf_range(SPARK_SPEED_MIN, SPARK_SPEED_MAX)

	var idx := _spark_count * SPARK_STRIDE
	_sparks[idx]     = p.x
	_sparks[idx + 1] = p.y
	_sparks[idx + 2] = v.x
	_sparks[idx + 3] = v.y
	_sparks[idx + 4] = 0.0
	_sparks[idx + 5] = randf_range(0.08, 0.2)
	_sparks[idx + 6] = randf_range(0.7, 1.3)
	_spark_count += 1


func _atualizar_faiscas(delta: float) -> void:
	var drag := 1.0 - minf(delta * 6.0, 0.95)
	var i := 0
	while i < _spark_count:
		var idx := i * SPARK_STRIDE
		var age: float = _sparks[idx + 4] + delta
		if age >= _sparks[idx + 5]:
			_spark_count -= 1
			if i != _spark_count:
				var last := _spark_count * SPARK_STRIDE
				for k in SPARK_STRIDE:
					_sparks[idx + k] = _sparks[last + k]
			continue
		_sparks[idx + 4] = age
		_sparks[idx]     += _sparks[idx + 2] * delta
		_sparks[idx + 1] += _sparks[idx + 3] * delta
		_sparks[idx + 2] *= drag
		_sparks[idx + 3] *= drag
		i += 1


# ═══════════ RENDER ARCOS + FAÍSCAS ═══════════
func _render_bolts(target: Control) -> void:
	if _intensidade > 0.0:
		var a := _intensidade
		var flick := 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.04)

		for pts: PackedVector2Array in _arcos:
			if pts.size() < 2:
				continue
			# Halo → corpo → núcleo (finos)
			target.draw_polyline(pts, Color(COR_RAIO_OUT, a * 0.35),        4.0, true)
			target.draw_polyline(pts, Color(COR_RAIO_MID, a * 0.70 * flick), 2.0, true)
			target.draw_polyline(pts, Color(COR_RAIO_CORE, a),               0.9, true)

	for i in _spark_count:
		var idx := i * SPARK_STRIDE
		var life := 1.0 - _sparks[idx + 4] / _sparks[idx + 5]
		if life <= 0.0:
			continue
		var px := _sparks[idx]
		var py := _sparks[idx + 1]
		target.draw_line(
			Vector2(px, py),
			Vector2(px - _sparks[idx + 2] * 0.03, py - _sparks[idx + 3] * 0.03),
			Color(COR_SPARK, life * 0.9),
			_sparks[idx + 6] * life, true
		)


# ═══════════ RENDER DO FORMATO ═══════════
func _paint(target: Control) -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0:
		return

	var active := _hover
	var pressed := button_pressed
	var focus_only := _has_focus and not _hover

	if active:
		var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.008)
		var gr := w * 0.75
		target.draw_texture_rect(_glow_tex,
			Rect2(-gr * 0.3, -gr * 0.4, w + gr * 0.6, h + gr * 0.8), false,
			Color(COR_GLOW, 0.55 * pulse))
		var gr2 := w * 0.5
		target.draw_texture_rect(_glow_tex,
			Rect2(-gr2 * 0.2, -gr2 * 0.3, w + gr2 * 0.4, h + gr2 * 0.6), false,
			Color(COR_BORDA_HOVER, 0.35 * pulse))

	var c := CHAMFER
	var pts := PackedVector2Array([
		Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c),
	])

	var col_top := COR_FUNDO_HOVER if active else COR_FUNDO_NORMAL
	if pressed:
		col_top = COR_FUNDO_PRESSED
	var col_mid := col_top.lerp(Color.WHITE, 0.05)
	var col_bot := col_top.darkened(0.45)
	var colors := PackedColorArray([
		col_top, col_top, col_mid, col_bot, col_bot, col_bot, col_mid, col_top
	])
	target.draw_polygon(pts, colors)

	var outline := pts.duplicate()
	outline.append(pts[0])
	var cor_borda := COR_BORDA_HOVER if (active or focus_only) else COR_BORDA
	target.draw_polyline(outline, cor_borda, 2.0, true)

	var ic := c * 0.5
	var ipts := PackedVector2Array([
		Vector2(ic + 3, 3), Vector2(w - ic - 3, 3), Vector2(w - 3, ic + 3),
		Vector2(w - 3, h - ic - 3), Vector2(w - ic - 3, h - 3), Vector2(ic + 3, h - 3),
		Vector2(3, h - ic - 3), Vector2(3, ic + 3)
	])
	ipts.append(ipts[0])
	target.draw_polyline(ipts, Color(cor_borda, 0.35), 1.0, true)

	var ac := COR_ACCENT if active else Color(COR_BORDA, 0.85)
	var al := 16.0
	var off := 5.0
	target.draw_line(Vector2(c + off, off), Vector2(c + off + al, off), ac, 2.5)
	target.draw_line(Vector2(off, c + off), Vector2(off, c + off + al), ac, 2.5)
	target.draw_line(Vector2(w - c - off - al, off), Vector2(w - c - off, off), ac, 2.5)
	target.draw_line(Vector2(w - off, c + off), Vector2(w - off, c + off + al), ac, 2.5)
	target.draw_line(Vector2(c + off, h - off), Vector2(c + off + al, h - off), ac, 2.5)
	target.draw_line(Vector2(off, h - c - off - al), Vector2(off, h - c - off), ac, 2.5)
	target.draw_line(Vector2(w - c - off - al, h - off), Vector2(w - c - off, h - off), ac, 2.5)
	target.draw_line(Vector2(w - off, h - c - off - al), Vector2(w - off, h - c - off), ac, 2.5)

	target.draw_line(
		Vector2(c + 6, 2.5), Vector2(w - c - 6, 2.5),
		Color(COR_GLOW, 0.6 if active else 0.35), 1.0
	)


func _get_glow_tex() -> void:
	if _glow_tex != null:
		return
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.15),
		Color(1, 1, 1, 0),
	])
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 128
	_glow_tex.height = 128
