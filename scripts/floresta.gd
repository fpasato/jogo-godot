extends Node2D

@onready var chao: TileMapLayer = $Chao

# --- Configurações de Geração ---
# A imagem TX Tileset Grass.png tem 256x256 pixels.
# Como cada tile tem 16x16 pixels, a imagem completa é uma grade de 16x16 tiles.
const CHUNK_SIZE: int = 16          # 16 tiles = 256 pixels (o tamanho exato da sua textura completa)
const CHUNK_RADIUS: int = 4         # Raio de chunks ao redor do player (cobre a tela toda com folga)
const UNLOAD_DISTANCE: int = 6     # Distância para descarregar chunks antigos

# Source 0 = TX Tileset Grass.png
const SOURCE_GRASS: int = 0

var player: Node2D
var chunks_carregados: Dictionary = {}
var ultimo_chunk: Vector2i = Vector2i(999999, 999999)

func _ready() -> void:
	# Limpa qualquer tile antigo desenhado manualmente
	chao.clear()
	
	player = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
		if not player:
			return
	
	# Posição do jogador em coordenadas de chunk
	var tile_pos = chao.local_to_map(chao.to_local(player.global_position))
	var chunk_atual = Vector2i(
		int(floor(float(tile_pos.x) / CHUNK_SIZE)),
		int(floor(float(tile_pos.y) / CHUNK_SIZE))
	)
	
	# Só atualiza quando o jogador muda de chunk (economia de processamento)
	if chunk_atual != ultimo_chunk:
		ultimo_chunk = chunk_atual
		atualizar_chunks(chunk_atual)

func atualizar_chunks(centro: Vector2i) -> void:
	# 1. Carrega os chunks no raio de visão
	for x in range(centro.x - CHUNK_RADIUS, centro.x + CHUNK_RADIUS + 1):
		for y in range(centro.y - CHUNK_RADIUS, centro.y + CHUNK_RADIUS + 1):
			var pos = Vector2i(x, y)
			if not chunks_carregados.has(pos):
				gerar_chunk(pos)
				
	# 2. Descarrega chunks distantes
	var para_remover: Array[Vector2i] = []
	for pos in chunks_carregados.keys():
		if abs(pos.x - centro.x) > UNLOAD_DISTANCE or abs(pos.y - centro.y) > UNLOAD_DISTANCE:
			para_remover.append(pos)
			
	for pos in para_remover:
		remover_chunk(pos)

func gerar_chunk(pos: Vector2i) -> void:
	chunks_carregados[pos] = true
	var start_x = pos.x * CHUNK_SIZE
	var start_y = pos.y * CHUNK_SIZE
	
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			var cell = Vector2i(x, y)
			
			# Mapeia para a posição exata (0 a 15) dentro da textura TX Tileset Grass.png (16x16 tiles)
			# Isso faz a imagem INTEIRA com todas as flores, folhagens e detalhes se repetir perfeitamente!
			var atlas_coord = Vector2i(posmod(x, 16), posmod(y, 16))
			
			chao.set_cell(cell, SOURCE_GRASS, atlas_coord)

func remover_chunk(pos: Vector2i) -> void:
	chunks_carregados.erase(pos)
	var start_x = pos.x * CHUNK_SIZE
	var start_y = pos.y * CHUNK_SIZE
	
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			chao.erase_cell(Vector2i(x, y))
