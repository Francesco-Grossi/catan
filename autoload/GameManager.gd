extends Node

# ── Enums ──────────────────────────────────────────────────────────────────
enum Phase { SETUP_SETTLEMENT, SETUP_ROAD, ROLL, BUILD, END_TURN }
enum Resource { WOOD, BRICK, ORE, WHEAT, SHEEP }
enum Terrain { WOOD, BRICK, ORE, WHEAT, SHEEP, DESERT }
enum Building { NONE, SETTLEMENT, CITY }

# ── Signals ────────────────────────────────────────────────────────────────
signal phase_changed(new_phase: Phase)
signal turn_changed(player_index: int)
signal resources_changed(player_index: int)
signal dice_rolled(die1: int, die2: int, total: int)
signal game_over(winner_index: int)
signal robber_moved()
signal log_message(msg: String)

# ── Constants ──────────────────────────────────────────────────────────────
const WINNING_VP := 10

const BUILD_COSTS: Dictionary = {
	"road":       { Resource.WOOD: 1, Resource.BRICK: 1 },
	"settlement": { Resource.WOOD: 1, Resource.BRICK: 1, Resource.WHEAT: 1, Resource.SHEEP: 1 },
	"city":       { Resource.ORE: 3, Resource.WHEAT: 2 },
	"dev_card":   { Resource.ORE: 1, Resource.WHEAT: 1, Resource.SHEEP: 1 },
}

const TERRAIN_TO_RESOURCE: Dictionary = {
	Terrain.WOOD:  Resource.WOOD,
	Terrain.BRICK: Resource.BRICK,
	Terrain.ORE:   Resource.ORE,
	Terrain.WHEAT: Resource.WHEAT,
	Terrain.SHEEP: Resource.SHEEP,
}

const TERRAIN_COUNTS: Dictionary = {
	Terrain.WOOD:  4,
	Terrain.BRICK: 3,
	Terrain.ORE:   3,
	Terrain.WHEAT: 4,
	Terrain.SHEEP: 4,
	Terrain.DESERT: 1,
}

const NUMBER_TOKENS: Array = [5, 2, 6, 3, 8, 10, 9, 12, 11, 4, 8, 10, 9, 4, 5, 6, 3, 11]

# ── State ──────────────────────────────────────────────────────────────────
var players: Array[PlayerData] = []
var current_player_index: int = 0
var current_phase: Phase = Phase.SETUP_SETTLEMENT
var setup_round: int = 0          # 0 = forward, 1 = backward
var setup_placements: int = 0     # settlements placed this round

var robber_hex: HexData = null    # hex currently holding the robber

var dev_card_deck: Array[String] = []

# Board data — populated by Board.gd
var hex_map: Dictionary = {}      # Vector2i(q,r) → HexData
var vertices: Array = []          # VertexPoint nodes
var edges: Array = []             # EdgePoint nodes

# ── Lifecycle ──────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_dev_deck()

func init_players(count: int) -> void:
	players.clear()
	var colors := [Color.RED, Color.BLUE, Color(0.1, 0.8, 0.1), Color.WHITE]
	for i in count:
		var p := PlayerData.new()
		p.player_index = i
		p.color = colors[i]
		players.append(p)
	current_player_index = 0
	current_phase = Phase.SETUP_SETTLEMENT
	setup_round = 0
	setup_placements = 0

# ── Phase helpers ──────────────────────────────────────────────────────────
func get_current_player() -> PlayerData:
	return players[current_player_index]

func advance_setup() -> void:
	setup_placements += 1
	if current_phase == Phase.SETUP_SETTLEMENT:
		current_phase = Phase.SETUP_ROAD
		phase_changed.emit(current_phase)
		return

	# after placing road, advance player order
	current_phase = Phase.SETUP_SETTLEMENT
	var total := players.size() * 2
	if setup_placements >= total:
		# Setup finished
		current_phase = Phase.ROLL
		phase_changed.emit(current_phase)
		turn_changed.emit(current_player_index)
		return

	if setup_round == 0:
		if current_player_index < players.size() - 1:
			current_player_index += 1
		else:
			setup_round = 1  # reverse direction
	else:
		if current_player_index > 0:
			current_player_index -= 1

	phase_changed.emit(current_phase)
	turn_changed.emit(current_player_index)

func roll_dice() -> void:
	if current_phase != Phase.ROLL:
		return
	var d1 := randi_range(1, 6)
	var d2 := randi_range(1, 6)
	var total := d1 + d2
	dice_rolled.emit(d1, d2, total)
	log_message.emit("Player %d rolled %d + %d = %d" % [current_player_index + 1, d1, d2, total])
	if total == 7:
		_handle_seven()
	else:
		_distribute_resources(total)
	current_phase = Phase.BUILD
	phase_changed.emit(current_phase)

func end_turn() -> void:
	if current_phase != Phase.BUILD:
		return
	_check_victory()
	current_player_index = (current_player_index + 1) % players.size()
	current_phase = Phase.ROLL
	phase_changed.emit(current_phase)
	turn_changed.emit(current_player_index)

# ── Building ───────────────────────────────────────────────────────────────
func can_afford(player_idx: int, item: String) -> bool:
	var p := players[player_idx]
	for res: Resource in BUILD_COSTS[item]:
		if p.resources.get(res, 0) < BUILD_COSTS[item][res]:
			return false
	return true

func spend(player_idx: int, item: String) -> void:
	var p := players[player_idx]
	for res: Resource in BUILD_COSTS[item]:
		p.resources[res] -= BUILD_COSTS[item][res]
	resources_changed.emit(player_idx)

func build_settlement(player_idx: int, vertex: Node) -> bool:
	if not can_afford(player_idx, "settlement") and not _is_setup_phase():
		return false
	if not vertex.can_place_settlement(player_idx):
		return false
	if not _is_setup_phase():
		spend(player_idx, "settlement")
	vertex.place_settlement(player_idx)
	players[player_idx].settlements += 1
	players[player_idx].victory_points += 1
	if _is_setup_phase() and setup_round == 1:
		_give_setup_resources(vertex)
	resources_changed.emit(player_idx)
	log_message.emit("Player %d built a settlement" % (player_idx + 1))
	return true

func build_city(player_idx: int, vertex: Node) -> bool:
	if not can_afford(player_idx, "city"):
		return false
	if vertex.owner != player_idx or vertex.building != GameManager.Building.SETTLEMENT:
		return false
	spend(player_idx, "city")
	vertex.upgrade_to_city()
	players[player_idx].settlements -= 1
	players[player_idx].cities += 1
	players[player_idx].victory_points += 1
	resources_changed.emit(player_idx)
	log_message.emit("Player %d built a city" % (player_idx + 1))
	return true

func build_road(player_idx: int, edge: Node) -> bool:
	if not can_afford(player_idx, "road") and not _is_setup_phase():
		return false
	if not edge.can_place_road(player_idx):
		return false
	if not _is_setup_phase():
		spend(player_idx, "road")
	edge.place_road(player_idx)
	players[player_idx].roads += 1
	_update_longest_road()
	log_message.emit("Player %d built a road" % (player_idx + 1))
	return true

func buy_dev_card(player_idx: int) -> bool:
	if dev_card_deck.is_empty():
		return false
	if not can_afford(player_idx, "dev_card"):
		return false
	spend(player_idx, "dev_card")
	var card := dev_card_deck.pop_back()
	players[player_idx].dev_cards.append(card)
	resources_changed.emit(player_idx)
	log_message.emit("Player %d bought a dev card" % (player_idx + 1))
	return true

# ── Trading ────────────────────────────────────────────────────────────────
func bank_trade(player_idx: int, give_res: Resource, receive_res: Resource) -> bool:
	var p := players[player_idx]
	var rate := _get_trade_rate(player_idx, give_res)
	if p.resources.get(give_res, 0) < rate:
		return false
	p.resources[give_res] -= rate
	p.resources[receive_res] = p.resources.get(receive_res, 0) + 1
	resources_changed.emit(player_idx)
	log_message.emit("Player %d traded %d %s for 1 %s" % [player_idx + 1, rate,
		Resource.keys()[give_res], Resource.keys()[receive_res]])
	return true

# ── Robber ─────────────────────────────────────────────────────────────────
func move_robber(hex: HexData) -> void:
	if robber_hex:
		robber_hex.has_robber = false
	robber_hex = hex
	hex.has_robber = true
	robber_moved.emit()
	log_message.emit("Robber moved to hex (%d,%d)" % [hex.q, hex.r])

# ── Private ────────────────────────────────────────────────────────────────
func _is_setup_phase() -> bool:
	return current_phase in [Phase.SETUP_SETTLEMENT, Phase.SETUP_ROAD]

func _distribute_resources(number: int) -> void:
	for hex: HexData in hex_map.values():
		if hex.number == number and not hex.has_robber and hex.terrain != Terrain.DESERT:
			var res: Resource = TERRAIN_TO_RESOURCE[hex.terrain]
			for v in hex.vertex_nodes:
				if v.owner >= 0:
					var amount := 2 if v.building == Building.CITY else 1
					players[v.owner].resources[res] = players[v.owner].resources.get(res, 0) + amount
					resources_changed.emit(v.owner)

func _handle_seven() -> void:
	for i in players.size():
		var total_res := 0
		for res: Resource in Resource.values():
			total_res += players[i].resources.get(res, 0)
		if total_res > 7:
			var to_discard := total_res / 2
			# AI: discard randomly; human would open a UI
			_discard_random(i, to_discard)
	# Signal UI to let current player move robber
	log_message.emit("7 rolled! Move the robber.")

func _discard_random(player_idx: int, count: int) -> void:
	var p := players[player_idx]
	var discarded := 0
	while discarded < count:
		var keys := Resource.values().filter(func(r): return p.resources.get(r, 0) > 0)
		if keys.is_empty():
			break
		var r: Resource = keys[randi() % keys.size()]
		p.resources[r] -= 1
		discarded += 1
	resources_changed.emit(player_idx)

func _give_setup_resources(vertex: Node) -> void:
	for hex: HexData in vertex.adjacent_hexes:
		if hex.terrain != Terrain.DESERT:
			var res: Resource = TERRAIN_TO_RESOURCE[hex.terrain]
			players[current_player_index].resources[res] = \
				players[current_player_index].resources.get(res, 0) + 1

func _get_trade_rate(player_idx: int, res: Resource) -> int:
	# Check ports — vertices owned by player with port
	for v in vertices:
		if v.owner == player_idx and v.port_type != -1:
			if v.port_type == res or v.port_type == 5:  # 5 = 3:1
				return 2 if v.port_type == res else 3
	return 4

func _update_longest_road() -> void:
	var best_player := -1
	var best_length := 4  # must exceed 4 to claim
	for i in players.size():
		var length := _calculate_longest_road(i)
		players[i].longest_road_length = length
		if length > best_length:
			best_length = length
			best_player = i

	# Transfer longest road card
	for i in players.size():
		if players[i].has_longest_road and i != best_player:
			players[i].has_longest_road = false
			players[i].victory_points -= 2
			resources_changed.emit(i)
	if best_player >= 0 and not players[best_player].has_longest_road:
		players[best_player].has_longest_road = true
		players[best_player].victory_points += 2
		resources_changed.emit(best_player)
		log_message.emit("Player %d has Longest Road!" % (best_player + 1))

func _calculate_longest_road(player_idx: int) -> int:
	var player_edges := edges.filter(func(e): return e.road_owner == player_idx)
	var best := 0
	for start_edge in player_edges:
		for start_vertex in start_edge.vertex_nodes:
			var visited_edges: Array = []
			var length := _dfs_road(player_idx, start_vertex, null, visited_edges)
			best = max(best, length)
	return best

func _dfs_road(player_idx: int, vertex: Node, came_from_edge: Node,
		visited: Array) -> int:
	var best := 0
	for edge in vertex.adjacent_edges:
		if edge == came_from_edge or edge in visited or edge.road_owner != player_idx:
			continue
		visited.append(edge)
		var next_vertex := edge.other_vertex(vertex)
		# Road blocked by opponent's building
		if next_vertex.owner >= 0 and next_vertex.owner != player_idx:
			visited.pop_back()
			continue
		var length := 1 + _dfs_road(player_idx, next_vertex, edge, visited)
		best = max(best, length)
		visited.pop_back()
	return best

func _build_dev_deck() -> void:
	dev_card_deck.clear()
	for _i in 14: dev_card_deck.append("knight")
	for _i in 5:  dev_card_deck.append("victory_point")
	for _i in 2:  dev_card_deck.append("road_building")
	for _i in 2:  dev_card_deck.append("year_of_plenty")
	for _i in 2:  dev_card_deck.append("monopoly")
	dev_card_deck.shuffle()

func _check_victory() -> void:
	for i in players.size():
		if players[i].victory_points >= WINNING_VP:
			game_over.emit(i)
			log_message.emit("🎉 Player %d wins!" % (i + 1))
			return
