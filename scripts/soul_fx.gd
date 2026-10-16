extends Node2D

@export var radius := 8.0
@export var soul_color := Color(1.0, 1.0, 1.0)   # cor do brilho (branco por padrão)
@export var animate_idle := true

const FLAME_POINTS := 14

var phase := 0.0
var time := 0.0

func _ready():
	phase = randf() * TAU   # cada alma balança em um ritmo diferente
	# Blend aditivo: o brilho "acende" o que está atrás
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

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
		var sway := sin(time * 7.0 + t * 3.5 + phase) * w * 0.35 * t * t * flicker
		sway += sin(time * 11.0 + t * 6.0 + phase * 2.0) * w * 0.12 * t
		var y := -t * h
		left.append(Vector2(-width + sway, y))
		right.append(Vector2(width + sway, y))
	right.reverse()
	left.append_array(right)
	return left

func _draw():
	var pulse := 1.0 + 0.08 * sin(time * 9.0 + phase)
	var r := radius * pulse
	var bob := sin(time * 3.0 + phase) * r * 0.15
	var base := Vector2(0, r * 0.9 + bob)

	# Brilho suave em volta (vários círculos com alpha baixo)
	var glow_center := base + Vector2(0, -r * 1.1)
	for i in 5:
		var k := 1.0 - float(i) / 5.0
		draw_circle(glow_center, r * (1.2 + (1.0 - k) * 2.6), Color(soul_color, 0.035 + 0.02 * k))

	# Chama em 3 camadas: externa azulada, meio, núcleo branco
	draw_set_transform(base, 0.0, Vector2.ONE)
	draw_colored_polygon(_flame_polygon(r * 3.0, r * 1.0, 1.0), Color(0.75, 0.85, 1.0, 0.35))
	draw_colored_polygon(_flame_polygon(r * 2.4, r * 0.75, 0.8), Color(soul_color, 0.7))
	draw_colored_polygon(_flame_polygon(r * 1.6, r * 0.42, 0.5), Color(1, 1, 1, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Faíscas subindo
	for i in 4:
		var p := fmod(time * 0.9 + float(i) / 4.0 + phase, 1.0)
		var x := sin(time * 2.0 + i * 2.3 + phase) * r * 0.7
		var pos := base + Vector2(x, -r * 1.2 - p * r * 3.2)
		draw_circle(pos, r * 0.12 * (1.0 - p) + 0.4, Color(1, 1, 1, (1.0 - p) * 0.9))

func play_collect_effect():
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(2.8, 2.8), 0.22)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.22)
	tween.tween_callback(queue_free)
