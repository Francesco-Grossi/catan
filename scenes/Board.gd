extends Node2D

const HEX_SIZE := 80.0

const HEX_COORDS: Array[Vector2i] = [
	Vector2i(0,-2), Vector2i(1,-2), Vector2i(2,-2),
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(2,-1),
	Vector2i(-2,0), Vector2i(-1,0), Vector2i(0,0), Vector2i(1,0), Vector2i(2,0),
	Vector2i(-2,1), Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1),
	Vector2i(-2,2), Vector2i(-1,2), Vector2i(0,2),
]

const HEX_DIRS: Array[Vector2i] = [
	Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1),
	Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,1),
]

const PORT_COLORS: Dictionary = {
	0: Color(0.13, 0.55, 0.13, 0.85),
	1: Color(0.78, 0.31, 0.08, 0.85),
	2: Color(0.55, 0.55, 0.55, 0.85),
	3: Color(0.93, 0.83, 0.10, 0.85),
	4: Color(0.56, 0.93, 0.56, 0.85),
	5: Color(0.9, 0.9, 0.9, 0.75),
}
const PORT_LABELS: Dictionary = {
	0: "2:1
🌲", 1: "2:1
🧱", 2: "2:1
⛏",
	3: "2:1
🌾", 4: "2:1
🐑", 5: "3:1",
}

@onready var hex_container: Node2D = $HexTiles
@onready var vertex_container: Node2D = $Vertices
@onready var edge_container: Node2D = $Edges
@onready var token_container: Node2D = $NumberTokens
@onready var port_container: Node2D = $Ports

var HexTileScene := preload("res://scenes/HexTile.tscn")
var VertexScene := preload("res://scenes/VertexPoint.tscn")
var EdgeScene := preload("res://scenes/EdgePoint.tscn")

var _vertex_map: Dictionary = {}
var _edge_map: Dictionary = {}

func _ready() -> void:
	_generate_board()

func _generate_board() -> void:
	GameManager.hex_map.clear()
	GameManager.vertices.clear()
	GameManager.edges.clear()
	GameManager.robber_hex = null
	_vertex_map.clear()
	_edge_map.clear()
	for c in hex_container.get_children(): c.queue_free()
	for c in vertex_container.get_children(): c.queue_free()
	for c in edge_container.get_children(): c.queue_free()
	for c in token_container.get_children(): c.queue_free()
	for c in port_container.get_children(): c.queue_free()

	var terrains: Array = _build_terrain_list()
	var tokens: Array = GameManager.NUMBER_TOKENS.duplicate()
	var attempts := 0
	while true:
		attempts += 1
		terrains.shuffle()
		tokens.shuffle()
		if not _has_adjacent_hot_numbers(terrains, tokens):
			break
		if attempts > 200:
			break

	var token_idx := 0
	for i in HEX_COORDS.size():
		var coord := HEX_COORDS[i]
		var terrain: GameManager.Terrain = terrains[i]
		var number := 0
		if terrain != GameManager.Terrain.DESERT:
			number = tokens[token_idx]
			token_idx += 1

		var data := HexData.new()
		data.q = coord.x
		data.r = coord.y
		data.terrain = terrain
		data.number = number
		if terrain == GameManager.Terrain.DESERT:
			data.has_robber = true
			GameManager.robber_hex = data
		GameManager.hex_map[coord] = data

		var hex_node := HexTileScene.instantiate() as Node2D
		hex_node.position = _axial_to_pixel(coord)
		hex_container.add_child(hex_node)
		hex_node.setup(data)

	_create_vertices_and_edges()
	_link_hex_vertices()
	_place_ports()

func _has_adjacent_hot_numbers(terrains: Array, tokens: Array) -> bool:
	var number_map: Dictionary = {}
	var token_idx := 0
	for i in HEX_COORDS.size():
		var terrain: GameManager.Terrain = terrains[i]
		if terrain == GameManager.Terrain.DESERT:
			number_map[HEX_COORDS[i]] = 0
		else:
			number_map[HEX_COORDS[i]] = tokens[token_idx]
			token_idx += 1
	for coord in HEX_COORDS:
		var n: int = number_map[coord]
		if n != 6 and n != 8:
			continue
		for dir in HEX_DIRS:
			var nb := coord + dir
			if number_map.has(nb):
				var nb_n: int = number_map[nb]
				if nb_n == 6 or nb_n == 8:
					return true
	return false

func _axial_to_pixel(coord: Vector2i) -> Vector2:
	var offset := Vector2(300, -30)
	var x := HEX_SIZE * (3.0 / 2.0 * coord.x)
	var y := HEX_SIZE * (sqrt(3.0) / 2.0 * coord.x + sqrt(3.0) * coord.y)
	return Vector2(x, y) + offset

func _hex_corners(center: Vector2) -> Array[Vector2]:
	var corners: Array[Vector2] = []
	for i in 6:
		# CHANGE 30.0 to 0.0 to hit the CORNERS
		var angle := deg_to_rad(0.0 + 60.0 * i) 
		corners.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
	return corners

func _create_vertices_and_edges() -> void:
	for coord in GameManager.hex_map:
		var center := _axial_to_pixel(coord)
		var corners := _hex_corners(center)
		var corner_nodes: Array[Node2D] = []
		for corner in corners:
			var key := _snap_vec(corner)
			if not _vertex_map.has(key):
				var v := VertexScene.instantiate() as Node2D
				v.position = corner
				vertex_container.add_child(v)
				_vertex_map[key] = v
				GameManager.vertices.append(v)
			corner_nodes.append(_vertex_map[key])
		for i in 6:
			var v1: Node2D = corner_nodes[i]
			var v2: Node2D = corner_nodes[(i + 1) % 6]
			var ekey := _edge_key(v1, v2)
			if not _edge_map.has(ekey):
				var e := EdgeScene.instantiate() as Node2D
				e.position = (v1.position + v2.position) / 2.0
				e.rotation = (v2.position - v1.position).angle()
				edge_container.add_child(e)
				e.setup(v1, v2)
				_edge_map[ekey] = e
				GameManager.edges.append(e)
				v1.adjacent_edges.append(e)
				v2.adjacent_edges.append(e)

func _link_hex_vertices() -> void:
	for coord: Vector2i in GameManager.hex_map:
		var data: HexData = GameManager.hex_map[coord]
		var center := _axial_to_pixel(coord)
		var corners := _hex_corners(center)
		for corner in corners:
			var v = _vertex_map.get(_snap_vec(corner))
			if v:
				if not data.vertex_nodes.has(v):
					data.vertex_nodes.append(v)
				if not v.adjacent_hexes.has(data):
					v.adjacent_hexes.append(data)

func _place_ports() -> void:
	# 1. Clear previous markers
	for c in port_container.get_children(): 
		c.queue_free()

	# 2. Identify and sort coastal vertices clockwise
	var coastal_vertices: Array = []
	for v in GameManager.vertices:
		if v.adjacent_hexes.size() > 0 and v.adjacent_hexes.size() < 3:
			coastal_vertices.append(v)
	
	# Sort vertices by angle from the center (approx Vector2(300, -30)) to ensure clockwise order
	var center = Vector2(300, -30)
	coastal_vertices.sort_custom(func(a, b):
		return (a.position - center).angle() < (b.position - center).angle()
	)

	# 3. Apply the pattern: 2 specific (2:1), skip 4, 2 generic (3:1), skip 2
	var specific_port_types = [
		GameManager.ResType.WOOD,
		GameManager.ResType.BRICK,
		GameManager.ResType.ORE,
		GameManager.ResType.WHEAT,
		GameManager.ResType.SHEEP
	]
	var specific_idx = 0
	var i = 0
	
	while i < coastal_vertices.size():
		# Place 2 Specific Ports (2:1)
		var current_res = specific_port_types[specific_idx % specific_port_types.size()]
		for j in range(2):
			if i < coastal_vertices.size():
				_apply_port_to_vertex(coastal_vertices[i], current_res)
				i += 1
		specific_idx += 1
		
		# Skip 1 vertices
		i += 1
		
		# Place 2 Generic Ports (3:1)
		for j in range(2):
			if i < coastal_vertices.size():
				_apply_port_to_vertex(coastal_vertices[i], 5) # 5 is 3:1 in your code
				i += 1
				
		# Skip 1 vertices
		i += 1

func _apply_port_to_vertex(v: Node, type: int) -> void:
	v.port_type = type
	
	# 1. Determine Color and Label Text
	var port_color: Color
	var label_text: String
	
	if type == 5: # Generic 3:1 Port
		port_color = Color(0.5, 0.5, 0.5) # Grey
		label_text = "3:1"
	else: # Specific 2:1 Ports [cite: 18, 20]
		# Use the TERRAIN_COLORS you provided
		var colors = {
			0: Color(0.13, 0.55, 0.13),  # WOOD
			1: Color(0.78, 0.31, 0.08),  # BRICK
			2: Color(0.55, 0.55, 0.55),  # ORE
			3: Color(0.93, 0.83, 0.10),  # WHEAT
			4: Color(0.56, 0.93, 0.56),  # SHEEP
		}
		var icons = {0: "🌲", 1: "🧱", 2: "⛏", 3: "🌾", 4: "🐑"}
		
		port_color = colors.get(type, Color.WHITE)
		label_text = "2:1 " + icons.get(type, "")

	# 2. Create the Visual Marker (Small Circle)
	var circle = Polygon2D.new()
	var points = PackedVector2Array()
	var radius = 7.0
	for i in range(12):
		var a = i * TAU / 12
		points.append(Vector2(cos(a), sin(a)) * radius)
	
	circle.polygon = points
	circle.color = port_color
	circle.position = v.position
	port_container.add_child(circle)

	# 3. Create the Text Window (Label)
	var label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Small font settings via Label Settings (Godot 4.x)
	var settings = LabelSettings.new()
	settings.font_size = 14
	settings.outline_size = 3
	settings.outline_color = Color.BLACK
	label.label_settings = settings
	
	# Offset the text slightly so it doesn't overlap the circle perfectly
	# Direction is away from the center of the board
	var center = Vector2(300, -30) # Your map center 
	var dir = (v.position - center).normalized()
	label.position = v.position + (dir * 15.0) - Vector2(15, 10) # Centering adjustment
	
	port_container.add_child(label)
	
func _build_terrain_list() -> Array:
	var list: Array = []
	for terrain: GameManager.Terrain in GameManager.TERRAIN_COUNTS:
		for _i in GameManager.TERRAIN_COUNTS[terrain]:
			list.append(terrain)
	return list

func _snap_vec(v: Vector2) -> Vector2:
	return Vector2(snapped(v.x, 1.0), snapped(v.y, 1.0))

func _edge_key(a: Node, b: Node) -> String:
	var ids := [a.get_instance_id(), b.get_instance_id()]
	ids.sort()
	return "%d_%d" % [ids[0], ids[1]]
