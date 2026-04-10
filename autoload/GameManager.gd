extends Node

# ── Enums ──────────────────────────────────────────────────────────────────
enum Phase { SETUP_SETTLEMENT, SETUP_ROAD, ROLL, BUILD, MOVE_ROBBER, DISCARD, END_TURN }
enum ResType { WOOD, BRICK, ORE, WHEAT, SHEEP }
enum Terrain { WOOD, BRICK, ORE, WHEAT, SHEEP, DESERT }
enum Building { NONE, SETTLEMENT, CITY }

# ── Signals ────────────────────────────────────────────────────────────────
signal phase_changed(new_phase: int)
signal turn_changed(player_index: int)
signal resources_changed(player_index: int)
signal dice_rolled(die1: int, die2: int, total: int)
signal game_over(winner_index: int)
signal robber_moved()
signal log_message(msg: String)
# Emitted when a player must choose cards to discard (UI shows the discard panel)
signal discard_required(player_index: int, amount: int)
# Emitted when the robber must be placed (UI shows the prompt)
signal robber_placement_required()

# ── Constants ──────────────────────────────────────────────────────────────
const WINNING_VP := 10
const NUMBER_TOKENS: Array = [5, 2, 6, 3, 8, 10, 9, 12, 11, 4, 8, 10, 9, 4, 5, 6, 3, 11]

# ── Build costs ────────────────────────────────────────────────────────────
var BUILD_COSTS: Dictionary = {}
var TERRAIN_TO_RESOURCE: Dictionary = {}
var TERRAIN_COUNTS: Dictionary = {}

# ── State ──────────────────────────────────────────────────────────────────
var players: Array[PlayerData] = []
var current_player_index: int = 0
var current_phase: int = Phase.SETUP_SETTLEMENT
var setup_round: int = 0
var setup_placements: int = 0
var robber_hex = null
var dev_card_deck: Array[String] = []

# Discard state — exposed so UI.gd can read _discard_current_idx
var _discard_queue: Array = []       # each element is Array [player_idx, amount]
var _discard_current_idx: int = -1
var _discard_amount: int = 0

# Board data — populated by Board.gd
var hex_map: Dictionary = {}
var vertices: Array = []
var edges: Array = []

# ── Lifecycle ──────────────────────────────────────────────────────────────
func _ready() -> void:
	_init_dictionaries()
	_build_dev_deck()

func _init_dictionaries() -> void:
	BUILD_COSTS = {
		"road":       { ResType.WOOD: 1, ResType.BRICK: 1 },
		"settlement": { ResType.WOOD: 1, ResType.BRICK: 1, ResType.WHEAT: 1, ResType.SHEEP: 1 },
		"city":       { ResType.ORE: 3, ResType.WHEAT: 2 },
		"dev_card":   { ResType.ORE: 1, ResType.WHEAT: 1, ResType.SHEEP: 1 },
	}
	TERRAIN_TO_RESOURCE = {
		Terrain.WOOD:   ResType.WOOD,
		Terrain.BRICK:  ResType.BRICK,
		Terrain.ORE:    ResType.ORE,
		Terrain.WHEAT:  ResType.WHEAT,
		Terrain.SHEEP:  ResType.SHEEP,
	}
	TERRAIN_COUNTS = {
		Terrain.WOOD:   4,
		Terrain.BRICK:  3,
		Terrain.ORE:    3,
		Terrain.WHEAT:  4,
		Terrain.SHEEP:  4,
		Terrain.DESERT: 1,
	}

func init_players(count: int) -> void:
	players.clear()
	var colors := [Color.RED, Color.BLUE, Color(0.1, 0.8, 0.1), Color.WHITE]
	for i in count:
		var p := PlayerData.new()
		p.player_index = i
		p.color = colors[i]
		p.resources = {
			ResType.WOOD:  0,
			ResType.BRICK: 0,
			ResType.ORE:   0,
			ResType.WHEAT: 0,
			ResType.SHEEP: 0,
		}
		players.append(p)
	current_player_index = 0
	current_phase = Phase.SETUP_SETTLEMENT
	setup_round = 0
	setup_placements = 0

# ── Phase helpers ──────────────────────────────────────────────────────────
func get_current_player() -> PlayerData:
	return players[current_player_index]

func _is_setup_phase() -> bool:
	return current_phase == Phase.SETUP_SETTLEMENT or current_phase == Phase.SETUP_ROAD

func advance_setup() -> void:
	setup_placements += 1
	if current_phase == Phase.SETUP_SETTLEMENT:
		current_phase = Phase.SETUP_ROAD
		phase_changed.emit(current_phase)
		return

	current_phase = Phase.SETUP_SETTLEMENT
	var total := players.size() * 2
	if setup_placements >= total:
		current_phase = Phase.ROLL
		phase_changed.emit(current_phase)
		turn_changed.emit(current_player_index)
		return

	if setup_round == 0:
		if current_player_index < players.size() - 1:
			current_player_index += 1
		else:
			setup_round = 1
	else:
		if current_player_index > 0:
			current_player_index -= 1

	phase_changed.emit(current_phase)
	turn_changed.emit(current_player_index)

# ── Dice ───────────────────────────────────────────────────────────────────
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
	for res in BUILD_COSTS[item]:
		if p.resources.get(res, 0) < BUILD_COSTS[item][res]:
			return false
	return true

func spend(player_idx: int, item: String) -> void:
	var p := players[player_idx]
	for res in BUILD_COSTS[item]:
		p.resources[res] -= BUILD_COSTS[item][res]
	resources_changed.emit(player_idx)

func build_settlement(player_idx: int, vertex: Node) -> bool:
	if not _is_setup_phase() and not can_afford(player_idx, "settlement"):
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
		log_message.emit("Player %d cannot afford a city" % (player_idx + 1))
		return false
	# FIX [5]: direct property access instead of .get() which returns null on typed vars
	if vertex.building_owner != player_idx or vertex.building != Building.SETTLEMENT:
		log_message.emit("Player %d: must click your own settlement to upgrade" % (player_idx + 1))
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
	var is_free: bool = players[player_idx].free_roads > 0
	if not _is_setup_phase() and not is_free and not can_afford(player_idx, "road"):
		return false
	if not edge.can_place_road(player_idx):
		return false
	if is_free:
		players[player_idx].free_roads -= 1
		log_message.emit("Player %d used a free road (%d left)" % [player_idx + 1, players[player_idx].free_roads])
	elif not _is_setup_phase():
		spend(player_idx, "road")
	edge.place_road(player_idx)
	players[player_idx].roads += 1
	_update_longest_road()
	log_message.emit("Player %d built a road" % (player_idx + 1))
	return true

func buy_dev_card(player_idx: int) -> bool:
	if dev_card_deck.is_empty():
		log_message.emit("Dev card deck is empty!")
		return false
	if not can_afford(player_idx, "dev_card"):
		log_message.emit("Player %d cannot afford a dev card" % (player_idx + 1))
		return false
	spend(player_idx, "dev_card")
	var card: String = dev_card_deck.pop_back()
	players[player_idx].dev_cards.append(card)
	resources_changed.emit(player_idx)
	log_message.emit("Player %d bought a dev card: %s" % [player_idx + 1, card])
	return true

# FIX [2]: Play a dev card
func play_dev_card(player_idx: int, card: String) -> bool:
	if current_phase != Phase.BUILD:
		return false
	var p := players[player_idx]
	if not p.dev_cards.has(card):
		return false
	p.dev_cards.erase(card)
	resources_changed.emit(player_idx)
	match card:
		"knight":
			p.knights_played += 1
			log_message.emit("Player %d played a Knight!" % (player_idx + 1))
			_update_largest_army()
			current_phase = Phase.MOVE_ROBBER
			phase_changed.emit(current_phase)
			robber_placement_required.emit()
		"victory_point":
			p.victory_points += 1
			resources_changed.emit(player_idx)
			log_message.emit("Player %d played a Victory Point card!" % (player_idx + 1))
			_check_victory()
		"road_building":
			p.free_roads += 2
			resources_changed.emit(player_idx)
			log_message.emit("Player %d played Road Building — place 2 free roads" % (player_idx + 1))
		"year_of_plenty":
			log_message.emit("Player %d played Year of Plenty" % (player_idx + 1))
		"monopoly":
			log_message.emit("Player %d played Monopoly" % (player_idx + 1))
	return true

func play_year_of_plenty(player_idx: int, res1: int, res2: int) -> void:
	players[player_idx].resources[res1] = players[player_idx].resources.get(res1, 0) + 1
	players[player_idx].resources[res2] = players[player_idx].resources.get(res2, 0) + 1
	resources_changed.emit(player_idx)
	var names := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	log_message.emit("Player %d took %s and %s" % [player_idx + 1, names[res1], names[res2]])

func play_monopoly(player_idx: int, res: int) -> void:
	var total := 0
	for i in players.size():
		if i == player_idx:
			continue
		var amt: int = players[i].resources.get(res, 0)
		players[i].resources[res] = 0
		resources_changed.emit(i)
		total += amt
	players[player_idx].resources[res] = players[player_idx].resources.get(res, 0) + total
	resources_changed.emit(player_idx)
	var names := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	log_message.emit("Player %d monopolized %s — gained %d" % [player_idx + 1, names[res], total])

# ── Trading ────────────────────────────────────────────────────────────────
func bank_trade(player_idx: int, give_res: int, receive_res: int) -> bool:
	var p := players[player_idx]
	var rate := _get_trade_rate(player_idx, give_res)
	if p.resources.get(give_res, 0) < rate:
		return false
	p.resources[give_res] -= rate
	p.resources[receive_res] = p.resources.get(receive_res, 0) + 1
	resources_changed.emit(player_idx)
	var names := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	log_message.emit("Player %d traded %d %s → 1 %s" % [player_idx + 1, rate, names[give_res], names[receive_res]])
	return true

# ── Robber ─────────────────────────────────────────────────────────────────
# FIX [4]: only acts in MOVE_ROBBER phase
func move_robber(hex) -> void:
	if current_phase != Phase.MOVE_ROBBER:
		return
	if hex == robber_hex:
		log_message.emit("Must move robber to a different hex!")
		return
	if robber_hex != null:
		robber_hex.has_robber = false
	robber_hex = hex
	hex.has_robber = true
	robber_moved.emit()
	log_message.emit("Robber moved to (%d,%d)" % [hex.q, hex.r])
	current_phase = Phase.BUILD
	phase_changed.emit(current_phase)

# ── FIX [3]: Player-controlled discard ────────────────────────────────────
func _handle_seven() -> void:
	_discard_queue.clear()
	for i in players.size():
		var total_res := 0
		for res in ResType.values():
			total_res += players[i].resources.get(res, 0)
		if total_res > 7:
			var must: int = total_res / 2
			_discard_queue.append([i, must])
			log_message.emit("Player %d must discard %d resources" % [i + 1, must])
	log_message.emit("7 rolled! Move the robber after discards.")
	_start_next_discard()

func _start_next_discard() -> void:
	if _discard_queue.is_empty():
		current_phase = Phase.MOVE_ROBBER
		phase_changed.emit(current_phase)
		robber_placement_required.emit()
		return
	# FIX: explicit Array type annotation avoids the `:=` inference error
	var entry: Array = _discard_queue[0]
	_discard_current_idx = entry[0]
	_discard_amount = entry[1]
	_discard_queue.remove_at(0)
	current_phase = Phase.DISCARD
	phase_changed.emit(current_phase)
	discard_required.emit(_discard_current_idx, _discard_amount)

# Called by UI.gd with the chosen resources dictionary
func submit_discard(player_idx: int, chosen: Dictionary) -> void:
	if current_phase != Phase.DISCARD:
		return
	if player_idx != _discard_current_idx:
		return
	var total_chosen := 0
	for res in chosen:
		total_chosen += chosen[res]
	if total_chosen != _discard_amount:
		log_message.emit("Must discard exactly %d resources!" % _discard_amount)
		# Re-emit so the panel stays up
		discard_required.emit(_discard_current_idx, _discard_amount)
		return
	var p := players[player_idx]
	for res in chosen:
		p.resources[res] -= chosen[res]
	resources_changed.emit(player_idx)
	log_message.emit("Player %d discarded %d resources" % [player_idx + 1, _discard_amount])
	_start_next_discard()

# ── Private helpers ────────────────────────────────────────────────────────
func _distribute_resources(number: int) -> void:
	for hex in hex_map.values():
		if hex.number == number and not hex.has_robber and hex.terrain != Terrain.DESERT:
			var res: int = TERRAIN_TO_RESOURCE[hex.terrain]
			for v in hex.vertex_nodes:
				# Direct property access (not .get()) — these are typed vars on VertexPoint
				var v_owner: int = v.building_owner
				var v_building: int = v.building
				if v_owner >= 0:
					var amount: int = 2 if v_building == Building.CITY else 1
					players[v_owner].resources[res] = players[v_owner].resources.get(res, 0) + amount
					resources_changed.emit(v_owner)

func _give_setup_resources(vertex: Node) -> void:
	for hex in vertex.adjacent_hexes:
		if hex.terrain != Terrain.DESERT:
			var res: int = TERRAIN_TO_RESOURCE[hex.terrain]
			players[current_player_index].resources[res] = \
				players[current_player_index].resources.get(res, 0) + 1

func _get_trade_rate(player_idx: int, res: int) -> int:
	for v in vertices:
		if v.building_owner == player_idx and v.port_type != -1:
			if v.port_type == res:
				return 2        # specific 2:1 port
			elif v.port_type == 5:
				return 3        # generic 3:1 port
	return 4

func _update_longest_road() -> void:
	var best_player := -1
	var best_length := 4
	for i in players.size():
		var length := _calculate_longest_road(i)
		players[i].longest_road_length = length
		if length > best_length:
			best_length = length
			best_player = i
	for i in players.size():
		if players[i].has_longest_road and i != best_player:
			players[i].has_longest_road = false
			players[i].victory_points -= 2
			resources_changed.emit(i)
			log_message.emit("Player %d lost Longest Road!" % (i + 1))
	if best_player >= 0 and not players[best_player].has_longest_road:
		players[best_player].has_longest_road = true
		players[best_player].victory_points += 2
		resources_changed.emit(best_player)
		# FIX [7]: always log when longest road changes owner
		log_message.emit("🛣️ Player %d has Longest Road! (length %d)" % [best_player + 1, best_length])

func _update_largest_army() -> void:
	var best_player := -1
	var best_knights := 2
	for i in players.size():
		if players[i].knights_played > best_knights:
			best_knights = players[i].knights_played
			best_player = i
	for i in players.size():
		if players[i].has_largest_army and i != best_player:
			players[i].has_largest_army = false
			players[i].victory_points -= 2
			resources_changed.emit(i)
			log_message.emit("Player %d lost Largest Army!" % (i + 1))
	if best_player >= 0 and not players[best_player].has_largest_army:
		players[best_player].has_largest_army = true
		players[best_player].victory_points += 2
		resources_changed.emit(best_player)
		log_message.emit("⚔️ Player %d has Largest Army! (%d knights)" % [best_player + 1, best_knights])

func _calculate_longest_road(player_idx: int) -> int:
	var player_edges: Array = []
	for e in edges:
		if e.road_owner == player_idx:
			player_edges.append(e)
	var best: int = 0
	for start_edge in player_edges:
		for start_vertex in start_edge.vertex_nodes:
			var visited: Array = []
			var length: int = _dfs_road(player_idx, start_vertex, null, visited)
			best = max(best, length)
	return best

func _dfs_road(player_idx: int, vertex: Node, came_from_edge, visited: Array) -> int:
	var best: int = 0
	for edge in vertex.adjacent_edges:
		if edge == came_from_edge or visited.has(edge):
			continue
		if edge.road_owner != player_idx:
			continue
		visited.append(edge)
		var next_vertex: Node = edge.other_vertex(vertex)
		if next_vertex.building_owner != -1 and next_vertex.building_owner != player_idx:
			visited.pop_back()
			continue
		var length: int = 1 + _dfs_road(player_idx, next_vertex, edge, visited)
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
			log_message.emit("🎉 Player %d wins with %d VP!" % [i + 1, players[i].victory_points])
			return
