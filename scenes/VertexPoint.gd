extends Node2D

signal clicked(vertex: Node)

var owner: int = -1
var building: GameManager.Building = GameManager.Building.NONE
var adjacent_edges: Array = []
var adjacent_hexes: Array = []
var port_type: int = -1  # -1=none, 0-4=specific resource, 5=3:1

@onready var sprite: Node2D  = $Sprite
@onready var area: Area2D    = $Area2D

func _ready() -> void:
	area.input_event.connect(_on_input_event)
	_refresh_visual()

func can_place_settlement(player_idx: int) -> bool:
	if building != GameManager.Building.NONE:
		return false
	# Distance rule: no adjacent vertex can have a building
	for edge in adjacent_edges:
		for v in edge.vertex_nodes:
			if v != self and v.building != GameManager.Building.NONE:
				return false
	# During non-setup, must be connected by own road
	if not GameManager._is_setup_phase():
		var connected := false
		for edge in adjacent_edges:
			if edge.road_owner == player_idx:
				connected = true
				break
		if not connected:
			return false
	return true

func place_settlement(player_idx: int) -> void:
	owner = player_idx
	building = GameManager.Building.SETTLEMENT
	_refresh_visual()

func upgrade_to_city() -> void:
	building = GameManager.Building.CITY
	_refresh_visual()

func _refresh_visual() -> void:
	if not is_inside_tree():
		return
	match building:
		GameManager.Building.NONE:
			sprite.visible = false
		GameManager.Building.SETTLEMENT:
			sprite.visible = true
			sprite.modulate = GameManager.players[owner].color if owner >= 0 else Color.WHITE
			sprite.scale = Vector2(0.6, 0.6)
		GameManager.Building.CITY:
			sprite.visible = true
			sprite.modulate = GameManager.players[owner].color
			sprite.scale = Vector2(1.0, 1.0)

func _on_input_event(_viewport, event: InputEvent, _shape) -> void:
	if event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
