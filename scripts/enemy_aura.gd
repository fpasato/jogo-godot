extends Node2D

@export var radius := 10.0
@export var aura_color := Color(0.35, 0.05, 0.55)   # roxo escuro principal
@export var core_color := Color(0.12, 0.0, 0.2)     # núcleo quase preto-violeta
@export var rim_color := Color(0.6, 0.2, 0.9)       # borda/faíscas mais claras
@export var animate_idle := true
@export var intensity := 1.0                        # multiplica o alpha geral

const FLAME_POINTS := 14

var phase := 0.0
var time := 0.0

func _ready():
	phase = randf() * TAU
	# Aditivo deixa o roxo "brilhar"; se quiser algo mais pesado/sombrio,
	# troque por BLEND_MODE_MIX.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	show_behind_parent = true   # a aura fica atrás do sprite do inimigo

func _process(delta):
	if animate_idle:
		time += delta
	queue_redraw()

func _flame_polygon(h: float, w: float, flicker: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in FLAME_POINTS + 1:
		var t := float(i) / FLAME_POINTS
		var width := w * pow(sin(PI * pow(t, 0.65)), 0.8)
		var sway := sin(time * 6.0 + t * 3.5 + phase) * w * 0.4 * t * t * flicker
		sway += sin(time * 10.0 + t * 6.0 + phase * 2.0) * w * 0.14 * t
		var y := -t * h
		left.append(Vector2(-width + sway, y))
		right.append(Vector2(width + sway, y))
	right.reverse()
	left.append_array(right)
	return left

func _a(a: float) -> float:
	return clampf(a * intensity, 0.0, 1.0)

func _draw():
	var pulse := 1.0 + 0.1 * sin(time * 5.0 + phase)
	var r := radius * pulse
	var bob := sin(time * 2.5 + phase) * r * 0.1
	var base := Vector2(0, r * 0.9 + bob)

	# Brilho suave em volta (círculos concêntricos de alpha baixo)
	var glow_center := base + Vector2(0, -r * 0.9)
	for i in 6:
		var k := 1.0 - float(i) / 6.0
		draw_circle(glow_center, r * (1.2 + (1.0 - k) * 2.8),
			Color(aura_color, _a(0.04 + 0.025 * k)))

	# Chamas em 3 camadas: externa roxa, meio mais claro, núcleo escuro
	draw_set_transform(base, 0.0, Vector2.ONE)
	draw_colored_polygon(_flame_polygon(r * 3.2, r * 1.1, 1.0), Color(aura_color, _a(0.40)))
	draw_colored_polygon(_flame_polygon(r * 2.5, r * 0.8, 0.8), Color(rim_color, _a(0.35)))
	draw_colored_polygon(_flame_polygon(r * 1.7, r * 0.45, 0.5), Color(core_color, _a(0.85)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Faíscas sombrias subindo
	for i in 5:
		var p := fmod(time * 0.7 + float(i) / 5.0 + phase, 1.0)
		var x := sin(time * 1.8 + i * 2.3 + phase) * r * 0.8
		var pos := base + Vector2(x, -r * 1.0 - p * r * 3.4)
		draw_circle(pos, r * 0.12 * (1.0 - p) + 0.4, Color(rim_color, _a((1.0 - p) * 0.8)))
