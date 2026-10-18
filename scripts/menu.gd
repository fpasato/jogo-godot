extends Control

@onready var btn_historia: Button = $MarginContainer/VBoxContainer/BtnHistoria
@onready var btn_arcade: Button = $MarginContainer/VBoxContainer/BtnArcade
@onready var btn_config: Button = $MarginContainer/VBoxContainer/BtnConfig
@onready var btn_sair: Button = $MarginContainer/VBoxContainer/BtnSair

func _ready() -> void:
	MusicaManager.tocar_menu()
	btn_historia.pressed.connect(_on_historia)
	btn_arcade.pressed.connect(_on_arcade)
	btn_config.pressed.connect(_on_config)
	btn_sair.pressed.connect(_on_sair)
	btn_arcade.grab_focus()


func _on_historia() -> void:
	print("História ainda não foi criada")

func _on_arcade() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_config() -> void:
	print("Configurações ainda não foi criada")

func _on_sair() -> void:
	get_tree().quit()
