extends Node2D

@onready var board: Node2D = $Board
@onready var ui: CanvasLayer = $UI

func _ready() -> void:
	GameManager.init_players(4)
	# Board generates itself; after it's done, connect UI vertex/edge clicks
	await get_tree().process_frame
	ui._refresh_ui()
