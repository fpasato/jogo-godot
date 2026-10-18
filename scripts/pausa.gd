extends CanvasLayer

@onready var btn_continuar: Button = $Control/CenterContainer/VBoxContainer/BtnContinuar
@onready var btn_menu: Button = $Control/CenterContainer/VBoxContainer/BtnMenu
@onready var btn_sair: Button = $Control/CenterContainer/VBoxContainer/BtnSairPausa

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	btn_continuar.pressed.connect(_continuar)
	btn_menu.pressed.connect(_ir_para_menu)
	btn_sair.pressed.connect(func(): get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			_continuar()
		else:
			_pausar()
		get_viewport().set_input_as_handled()

func _pausar() -> void:
	visible = true
	get_tree().paused = true
	btn_continuar.grab_focus()

func _continuar() -> void:
	visible = false
	get_tree().paused = false

func _ir_para_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
