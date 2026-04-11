extends Node2D

@onready var board: Node2D = $Board
@onready var ui: CanvasLayer = $UI

func _ready() -> void:
	# Player count is chosen in the UI pre-game section and applied on Start.
	# We still call init_players here so GameManager.players is not empty
	# when _refresh_ui() runs its first pass, keeping the default at 4.
	GameManager.init_players(4)
	await get_tree().process_frame
	ui._refresh_ui()
