extends Node2D

signal clicked(vertex: Node)

var building_owner: int = -1
var building: int = 0        # 0 = NONE, 1 = SETTLEMENT, 2 = CITY
var adjacent_edges: Array = []
var adjacent_hexes: Array = []
var port_type: int = -1

@onready var sprite: ColorRect = $Sprite
@onready var area: Area2D = $Area2D

func _ready() -> void:
	area.input_event.connect(_on_input_event)
	_refresh_visual()

func can_place_settlement(player_idx: int) -> bool:
	if building != 0:	# 0 = NONE
		return false
	for edge in adjacent_edges:
		for v in edge.vertex_nodes:
			if v != self and v.building != 0:
				return false
	if not GameManager._is_setup_phase():
		var connected := false
		for edge in adjacent_edges:
			var edge_owner: int = edge.get("road_owner")
			if edge_owner == player_idx:
				connected = true
				break
		if not connected:
			return false
	return true

func place_settlement(player_idx: int) -> void:
	building_owner = player_idx
	building = 1	# SETTLEMENT
	_refresh_visual()

func upgrade_to_city() -> void:
	building = 2	# CITY
	_refresh_visual()

func _refresh_visual() -> void:
	if not is_inside_tree():
		return
	match building:
		0:	# NONE
			sprite.visible = false
		1:	# SETTLEMENT
			sprite.visible = true
			if building_owner >= 0 and not GameManager.players.is_empty():
				sprite.color = GameManager.players[building_owner].color
			sprite.size = Vector2(14.0, 14.0)
			sprite.position = Vector2(-7.0, -7.0)
		2:	# CITY
			sprite.visible = true
			if building_owner >= 0 and not GameManager.players.is_empty():
				sprite.color = GameManager.players[building_owner].color
			sprite.size = Vector2(20.0, 20.0)
			sprite.position = Vector2(-10.0, -10.0)

func _on_input_event(_viewport, event: InputEvent, _shape) -> void:
	if event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
