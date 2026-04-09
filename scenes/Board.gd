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

# Axial directions for neighbour lookup
const HEX_DIRS: Array[Vector2i] = [
	Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1),
	Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,1),
]

@onready var hex_container: Node2D  = $HexTiles
@onready var vertex_container: Node2D = $Vertices
@onready var edge_container: Node2D   = $Edges
@onready var token_container: Node2D  = $NumberTokens

var HexTileScene   := preload("res://scenes/HexTile.tscn")
var VertexScene    := preload("res://scenes/VertexPoint.tscn")
var EdgeScene      := preload("res://scenes/EdgePoint.tscn")

var _vertex_map: Dictionary = {}   # Vector2 (rounded pos) → VertexPoint
var _edge_map: Dictionary = {}     # String "v1_v2" → EdgePoint

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
		hex_node.setup(data)
		hex_container.add_child(hex_node)

	_create_vertices_and_edges()
	_link_hex_vertices()

func _axial_to_pixel(coord: Vector2i) -> Vector2:
	var x := HEX_SIZE * (3.0 / 2.0 * coord.x)
	var y := HEX_SIZE * (sqrt(3.0) / 2.0 * coord.x + sqrt(3.0) * coord.y)
	return Vector2(x, y)

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
		var corner_nodes: Array[Node] = []

		for corner in corners:
			var key := _snap_vec(corner)
			if not _vertex_map.has(key):
				var v := VertexScene.instantiate()
				v.position = corner
				vertex_container.add_child(v)
				_vertex_map[key] = v
				GameManager.vertices.append(v)
			corner_nodes.append(_vertex_map[key])

		# Create edges between adjacent corners
		for i in 6:
			var v1 := corner_nodes[i]
			var v2 := corner_nodes[(i + 1) % 6]
			var ekey := _edge_key(v1, v2)
			if not _edge_map.has(ekey):
				var e := EdgeScene.instantiate()
				e.position = (v1.position + v2.position) / 2.0
				var diff := v2.position - v1.position
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
