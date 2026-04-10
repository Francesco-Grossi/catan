extends Node2D

const HEX_SIZE := 80.0

# Standard Catan axial layout (19 hexes)
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

# Port colors for rendering
# [q, r, corner_start_index, port_type]
# port_type 0-4 = specific resource (matches ResType), 5 = generic 3:1
const PORT_DEFS: Array = [
	[ 0, -2, 4, 0],   # Wood  2:1
	[ 1, -2, 3, 5],   # Generic 3:1
	[ 2, -2, 3, 3],   # Wheat 2:1
	[ 2, -1, 2, 5],   # Generic 3:1
	[ 2,  0, 1, 4],   # Sheep 2:1
	[ 1,  1, 1, 5],   # Generic 3:1
	[ 0,  2, 0, 2],   # Ore   2:1
	[-1,  2, 5, 5],   # Generic 3:1
	[-2,  1, 5, 1],   # Brick 2:1
]

const PORT_COLORS: Dictionary = {
	0: Color(0.13, 0.55, 0.13, 0.85),   # Wood
	1: Color(0.78, 0.31, 0.08, 0.85),   # Brick
	2: Color(0.55, 0.55, 0.55, 0.85),   # Ore
	3: Color(0.93, 0.83, 0.10, 0.85),   # Wheat
	4: Color(0.56, 0.93, 0.56, 0.85),   # Sheep
	5: Color(0.9,  0.9,  0.9,  0.75),   # Generic 3:1
}
const PORT_LABELS: Dictionary = {
	0: "2:1\n🌲", 1: "2:1\n🧱", 2: "2:1\n⛏",
	3: "2:1\n🌾", 4: "2:1\n🐑", 5: "3:1",
}

@onready var hex_container: Node2D    = $HexTiles
@onready var vertex_container: Node2D = $Vertices
@onready var edge_container: Node2D   = $Edges
@onready var token_container: Node2D  = $NumberTokens
@onready var port_container: Node2D   = $Ports

var HexTileScene   := preload("res://scenes/HexTile.tscn")
var VertexScene    := preload("res://scenes/VertexPoint.tscn")
var EdgeScene      := preload("res://scenes/EdgePoint.tscn")

var _vertex_map: Dictionary = {}
var _edge_map: Dictionary = {}

func _ready() -> void:
	_generate_board()

func _generate_board() -> void:
	var terrains := _build_terrain_list()
	terrains.shuffle()
	var tokens := GameManager.NUMBER_TOKENS.duplicate()
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

func _axial_to_pixel(coord: Vector2i) -> Vector2:
	var offset := Vector2(300, -30)
	var x := HEX_SIZE * (3.0 / 2.0 * coord.x)
	var y := HEX_SIZE * (sqrt(3.0) / 2.0 * coord.x + sqrt(3.0) * coord.y)
	return Vector2(x, y) + offset

func _hex_corners(center: Vector2) -> Array[Vector2]:
	var corners: Array[Vector2] = []
	for i in 6:
		var angle := deg_to_rad(60.0 * i)
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
				var v := VertexScene.instantiate()
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
				var e := EdgeScene.instantiate()
				var pos1: Vector2 = v1.position
				var pos2: Vector2 = v2.position
				e.position = (pos1 + pos2) / 2.0
				var diff: Vector2 = pos2 - pos1
				e.rotation = diff.angle()
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
				data.vertex_nodes.append(v)
				v.adjacent_hexes.append(data)

func _place_ports() -> void:
	# PORT_DEFS: [q, r, edge_corner_start, port_type]
	# edge_corner_start: which corner index (0-5) starts the port edge
	# The two vertices of that edge are corner[i] and corner[(i+1)%6]
	for port_def in PORT_DEFS:
		var coord := Vector2i(port_def[0], port_def[1])
		var corner_idx: int = port_def[2]
		var port_type: int = port_def[3]

		if not GameManager.hex_map.has(coord):
			continue

		var center := _axial_to_pixel(coord)
		var corners := _hex_corners(center)

		var c1 := corners[corner_idx]
		var c2 := corners[(corner_idx + 1) % 6]

		# Assign port type to both vertices
		var v1 = _vertex_map.get(_snap_vec(c1))
		var v2 = _vertex_map.get(_snap_vec(c2))
		if v1:
			v1.port_type = port_type
		if v2:
			v2.port_type = port_type

		# Draw a port indicator between the two vertices (outside the hex)
		_draw_port_marker((c1 + c2) / 2.0, port_type)

func _draw_port_marker(pos: Vector2, port_type: int) -> void:
	var node := Node2D.new()
	node.position = pos
	port_container.add_child(node)

	# Background circle
	var rect := ColorRect.new()
	rect.size = Vector2(44, 30)
	rect.position = Vector2(-22, -15)
	rect.color = PORT_COLORS.get(port_type, Color.WHITE)
	node.add_child(rect)

	# Label
	var lbl := Label.new()
	lbl.text = PORT_LABELS.get(port_type, "?")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(44, 30)
	lbl.position = Vector2(-22, -15)
	lbl.add_theme_font_size_override("font_size", 9)
	node.add_child(lbl)

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
