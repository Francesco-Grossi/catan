extends Node2D

signal clicked(vertex: Node)

var building_owner: int = -1
var building: int = 0        # 0 = NONE, 1 = SETTLEMENT, 2 = CITY
var adjacent_edges: Array = []
var adjacent_hexes: Array = []
var port_type: int = -1

@onready var sprite: Polygon2D = $Sprite
@onready var area: Area2D = $Area2D

func _ready() -> void:
	area.input_event.connect(_on_input_event)
	_refresh_visual()

func can_place_settlement(player_idx: int) -> bool:
	if building != 0:
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
	building = 1
	_refresh_visual()

func upgrade_to_city() -> void:
	building = 2
	_refresh_visual()

func _refresh_visual() -> void:
	if not is_inside_tree():
		return
	var color := Color.WHITE
	if building_owner >= 0 and not GameManager.players.is_empty():
		color = GameManager.players[building_owner].color

	match building:
		0:  # NONE
			sprite.visible = false

		1:  # SETTLEMENT — small square
			sprite.visible = true
			sprite.color = color
			var s := 7.0
			sprite.polygon = PackedVector2Array([
				Vector2(-s, -s), Vector2(s, -s),
				Vector2(s,  s),  Vector2(-s,  s)
			])

		2:  # CITY — house shape: rectangle base + triangle roof
			sprite.visible = true
			sprite.color = color
			var bw := 9.0   # base half-width
			var bh := 7.0   # base half-height
			var rh := 9.0   # roof height above base top
			sprite.polygon = PackedVector2Array([
				Vector2(-bw,  bh),   # bottom-left
				Vector2( bw,  bh),   # bottom-right
				Vector2( bw, -bh),   # top-right of base
				Vector2(  0, -bh - rh),  # roof peak
				Vector2(-bw, -bh),   # top-left of base
			])

func _on_input_event(_viewport, event: InputEvent, _shape) -> void:
	if event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
