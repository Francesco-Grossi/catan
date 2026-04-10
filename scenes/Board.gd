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

# The 6 axial neighbour directions
const HEX_DIRS: Array[Vector2i] = [
	Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1),
	Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,1),
]

# ── Coastal edges in clockwise order ─────────────────────────────────────
# Each entry: [hex_q, hex_r, corner_index]
# corner_index: the two vertices of that coastal edge are corner[i] and corner[(i+1)%6]
# These 18 coastal edges go clockwise around the board starting from top-left.
# There are 18 coastal edges total; we place 9 ports (every other edge).
const COASTAL_EDGES: Array = [
	# Top row (left to right)
	[0,-2, 5], [1,-2, 5], [2,-2, 5],
	# Right side (top to bottom)
	[2,-2, 0], [2,-1, 0], [2,0, 0],
	# Bottom-right (right to left)
	[2,0, 1], [1,1, 1], [0,2, 1],
	# Bottom (right to left)
	[0,2, 2], [-1,2, 2], [-2,2, 2],
	# Left side (bottom to top)  — note: [-2,2] doesn't exist, use [-2,1] and [-2,0]
	[-2,1, 3], [-2,0, 3], [-2,-1, 3],  # [-2,-1] doesn't exist either
	# Top-left (bottom to top)
	[-1,-1, 4], [0,-2, 4], [1,-2, 4],
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

var HexTileScene := preload("res://scenes/HexTile.tscn")
var VertexScene  := preload("res://scenes/VertexPoint.tscn")
var EdgeScene    := preload("res://scenes/EdgePoint.tscn")

var _vertex_map: Dictionary = {}
var _edge_map: Dictionary   = {}

func _ready() -> void:
	_generate_board()

# ── FIX [3]: keep reshuffling until no 6/8 are adjacent to each other ─────
func _generate_board() -> void:
	var terrains: Array = _build_terrain_list()
	var tokens: Array   = GameManager.NUMBER_TOKENS.duplicate()

	# Shuffle terrain and tokens together until no 6 or 8 are neighbours
	var attempts := 0
	while true:
		attempts += 1
		terrains.shuffle()
		tokens.shuffle()
		if not _has_adjacent_hot_numbers(terrains, tokens):
			break
		if attempts > 200:   # safety valve — give up after 200 tries
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
		data.number  = number
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
	_place_ports()   # FIX [1]

# Returns true if any two neighbouring hexes both have "hot" numbers (6 or 8)
func _has_adjacent_hot_numbers(terrains: Array, tokens: Array) -> bool:
	# Build a temporary number map indexed by HEX_COORDS position
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
				if not data.vertex_nodes.has(v):
					data.vertex_nodes.append(v)
				if not v.adjacent_hexes.has(data):
					v.adjacent_hexes.append(data)

# ── FIX [1]: Algorithmic port placement ───────────────────────────────────
#
# Algorithm (matches your spec):
#   1. Collect all coastal edges in clockwise order (only edges whose
#      hex exists on the board and whose outward-facing neighbour does NOT).
#   2. Pick a random starting edge.
#   3. Place a 2:1 port there, skip 1 edge, place a 3:1 port, skip 1 edge,
#      repeat (alternating 2:1 / skip / 3:1 / skip) for 9 ports total.
#   4. The five 2:1 resource types are assigned in random order.
#
func _place_ports() -> void:
	# ── Step 1: gather valid coastal edges clockwise ─────────────────────
	# A coastal edge belongs to a land hex whose neighbour in the outward
	# direction is off the board.  We enumerate every hex edge and keep
	# those where the opposite hex doesn't exist.
	var coastal: Array = []   # each element: { hex: Vector2i, corner: int }

	# Walk the board border clockwise.  We use the known ring of border hexes
	# and for each one record which of its edges face outward (no neighbour).
	# To get a clean clockwise order we trace the outer ring explicitly.
	coastal = _collect_coastal_edges_clockwise()

	var n_coastal: int = coastal.size()
	if n_coastal == 0:
		return

	# ── Step 2: port type list ───────────────────────────────────────────
	# 5 specific 2:1 ports (one per resource) + 4 generic 3:1 ports = 9
	var specific_types: Array = [0, 1, 2, 3, 4]   # Wood Brick Ore Wheat Sheep
	specific_types.shuffle()

	# Port sequence: 2:1, skip, 3:1, skip, 2:1, skip, 3:1 … for 9 ports
	# Pattern of what we place at each selected edge (True = place, False = skip):
	# We place on edges at indices: 0, 2, 4, 6, 8, 10, 12, 14, 16  (every other)
	# Of those 9, slots 0,2,4,6,8 = specific; 1,3 of 3:1 fill the gaps.
	# Actually the rule says: 2:1, skip, 3:1, skip, 2:1, skip …
	# So the port types in order are: 2:1, 3:1, 2:1, 3:1, 2:1, 3:1, 2:1, 3:1, 2:1
	# That gives 5× 2:1 and 4× 3:1.
	var port_type_sequence: Array = []
	var spec_idx := 0
	for p_i in 9:
		if p_i % 2 == 0:
			port_type_sequence.append(specific_types[spec_idx])
			spec_idx += 1
		else:
			port_type_sequence.append(5)   # generic 3:1

	# ── Step 3: pick random start edge, then place every other edge ──────
	var start: int = randi() % n_coastal
	var port_idx := 0
	for step in 9:
		var edge_idx: int = (start + step * 2) % n_coastal
		var ce: Dictionary = coastal[edge_idx]
		var ptype: int = port_type_sequence[port_idx]
		port_idx += 1
		_apply_port(ce.hex, ce.corner, ptype)

# Collect all coastal edges in clockwise order.
# Strategy: trace the outer perimeter by following the border hexes clockwise,
# and for each border hex record the edges that have no land neighbour,
# in the order they face outward (clockwise).
func _collect_coastal_edges_clockwise() -> Array:
	# The outer ring of the Catan board in clockwise order starting top-left:
	var border_hexes: Array[Vector2i] = [
		Vector2i(0,-2), Vector2i(1,-2), Vector2i(2,-2),
		Vector2i(2,-1), Vector2i(2,0),
		Vector2i(1,1),  Vector2i(0,2),
		Vector2i(-1,2), Vector2i(-2,2),
		Vector2i(-2,1), Vector2i(-2,0),
		Vector2i(-1,-1),
	]

	# For each border hex, determine which of its 6 edges are coastal
	# (the neighbour in that direction is off the board).
	# Then sort those outward edges so they appear in clockwise order.
	#
	# Hex corner convention (flat-top):
	#   corner 0 = right, 1 = lower-right, 2 = lower-left,
	#   3 = left, 4 = upper-left, 5 = upper-right
	# Edge i connects corner[i] → corner[(i+1)%6]
	# Direction of hex_neighbour for each edge (outward normal):
	#   edge 0 → dir 0 (E),  edge 1 → dir 1 (SE), edge 2 → dir 2 (SW, but actually NE in our coords)
	# Let's use: edge i faces the neighbour in HEX_DIRS[i] direction.
	# Wait — edge i connects corner i and corner i+1.
	# The neighbour that shares this edge is in direction (i+2)%6... actually
	# the shared-edge neighbour relationship in axial flat-top is:
	#   edge 0 (right side, corners 0-1) → neighbour dir 0 = Vector2i(1,0)
	#   edge 1 (lower-right, corners 1-2) → neighbour dir 5 = Vector2i(0,1)
	#   edge 2 (lower-left, corners 2-3) → neighbour dir 4 = Vector2i(-1,1)
	#   edge 3 (left, corners 3-4) → neighbour dir 3 = Vector2i(-1,0)
	#   edge 4 (upper-left, corners 4-5) → neighbour dir 2 = Vector2i(0,-1)
	#   edge 5 (upper-right, corners 5-0) → neighbour dir 1 = Vector2i(1,-1)
	#
	# But our corners are pointy-top (angle = 60*i), so let's recalculate:
	# corner i = angle 60*i degrees.  The edge from corner i to corner i+1
	# faces outward in the direction perpendicular to that edge, which equals
	# the neighbour direction.  For pointy-top hexagons:
	#   edge 0 (corners 0-1, top-right) → neighbour Vector2i(1,-1)  (dir index 1)
	#   edge 1 (corners 1-2, right)     → neighbour Vector2i(1,0)   (dir index 0)
	#   edge 2 (corners 2-3, lower-right)→ neighbour Vector2i(0,1)  (dir index 5)
	#   edge 3 (corners 3-4, lower-left)→ neighbour Vector2i(-1,1)  (dir index 4)
	#   edge 4 (corners 4-5, left)      → neighbour Vector2i(-1,0)  (dir index 3)
	#   edge 5 (corners 5-0, upper-left)→ neighbour Vector2i(0,-1)  (dir index 2)
	#
	# HEX_DIRS = [Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1), Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,1)]
	# So edge_to_dir_index = [1, 0, 5, 4, 3, 2]
	var edge_to_dir: Array[int] = [1, 0, 5, 4, 3, 2]

	var result: Array = []
	for hex in border_hexes:
		# Find which edges of this hex are coastal, in clockwise order
		# We want the edges that face outward (their neighbour is not on the board).
		# We also need to output them in clockwise order around the perimeter.
		# For border hexes we collect all coastal edges in ascending corner order.
		var coastal_edges_of_hex: Array = []
		for edge_i in 6:
			var dir_idx: int = edge_to_dir[edge_i]
			var nb: Vector2i = hex + HEX_DIRS[dir_idx]
			if not GameManager.hex_map.has(nb):
				coastal_edges_of_hex.append(edge_i)
		# Add them in the order we encounter them (clockwise by corner index)
		for edge_i in coastal_edges_of_hex:
			result.append({ "hex": hex, "corner": edge_i })

	return result

func _apply_port(hex: Vector2i, corner_idx: int, port_type: int) -> void:
	var center := _axial_to_pixel(hex)
	var corners := _hex_corners(center)
	var c1 := corners[corner_idx]
	var c2 := corners[(corner_idx + 1) % 6]

	var v1 = _vertex_map.get(_snap_vec(c1))
	var v2 = _vertex_map.get(_snap_vec(c2))
	if v1:
		v1.port_type = port_type
	if v2:
		v2.port_type = port_type

	# Draw marker pushed outward from the hex center
	var mid := (c1 + c2) / 2.0
	var outward: Vector2 = (mid - center).normalized()
	_draw_port_marker(mid + outward * 18.0, port_type)

func _draw_port_marker(pos: Vector2, port_type: int) -> void:
	var node := Node2D.new()
	node.position = pos
	port_container.add_child(node)

	var rect := ColorRect.new()
	rect.size = Vector2(44, 30)
	rect.position = Vector2(-22, -15)
	rect.color = PORT_COLORS.get(port_type, Color.WHITE)
	node.add_child(rect)

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
