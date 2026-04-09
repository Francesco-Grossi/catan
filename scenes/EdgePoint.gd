extends Node2D

signal clicked(edge: Node)

var road_owner: int = -1
var vertex_nodes: Array = []   # the two VertexPoints this edge connects

@onready var line: ColorRect = $ColorRect
@onready var area: Area2D    = $Area2D

func setup(v1: Node, v2: Node) -> void:
	vertex_nodes = [v1, v2]
	area.input_event.connect(_on_input_event)
	_refresh_visual()

func other_vertex(v: Node) -> Node:
	return vertex_nodes[0] if v == vertex_nodes[1] else vertex_nodes[1]

func can_place_road(player_idx: int) -> bool:
	if road_owner != -1:
		return false
	# Must connect to own settlement or own road
	for v in vertex_nodes:
		if v.building_owner == player_idx:
			return true
		for edge in v.adjacent_edges:
			if edge != self and edge.road_owner == player_idx:
				# Check the path isn't blocked by opponent's building on shared vertex
				if v.building_owner == -1 or v.building_owner == player_idx:
					return true
	return false

func place_road(player_idx: int) -> void:
	road_owner = player_idx
	_refresh_visual()

func _refresh_visual() -> void:
	if not is_inside_tree():
		return
	if road_owner >= 0:
		line.color = GameManager.players[road_owner].color
		line.visible = true
	else:
		line.visible = false

func _on_input_event(_viewport, event: InputEvent, _shape) -> void:
	if event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
