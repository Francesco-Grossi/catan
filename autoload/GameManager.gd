extends Node

# ── Enums ──────────────────────────────────────────────────────────────────
enum Phase { PRE_GAME, SETUP_SETTLEMENT, SETUP_ROAD, ROLL, BUILD, MOVE_ROBBER, DISCARD, END_TURN }
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
signal discard_required(player_index: int, amount: int)
signal robber_placement_required()
signal steal_required(thief_index: int, victim_indices: Array)
# Player trade signals
signal trade_offer_sent(from_idx: int, to_idx: int, give: Dictionary, receive: Dictionary)
signal trade_offer_resolved()

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
var current_phase: int = Phase.PRE_GAME
var setup_round: int = 0
var setup_placements: int = 0
var robber_hex = null
var dev_card_deck: Array[String] = []

var _discard_queue: Array = []
var _discard_current_idx: int = -1
var _discard_amount: int = 0

# Board data — populated by Board.gd
var hex_map: Dictionary = {}
var vertices: Array = []
var edges: Array = []

# ── Undo State ────────────────────────────────────────────────────────────
# Stores the last build action so it can be undone once per turn
# Format: { "type": "road"/"settlement"/"city", "node": <Node>, "player_idx": int,
#           "cost": Dictionary, "was_setup": bool, "prev_building": int,
#           "prev_building_owner": int, "prev_road_owner": int,
#           "vp_delta": int, "settlements_delta": int, "cities_delta": int, "roads_delta": int }
var _undo_action: Dictionary = {}

# ── Trade State ───────────────────────────────────────────────────────────
var _trade_from_idx: int = -1
var _trade_to_idx: int = -1
var _trade_give: Dictionary = {}     # ResType → amount
var _trade_receive: Dictionary = {}  # ResType → amount

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
	current_phase = Phase.PRE_GAME
	setup_round = 0
	setup_placements = 0

# ── Pre-game ───────────────────────────────────────────────────────────────
func start_game() -> void:
	if current_phase == Phase.PRE_GAME:
		current_phase = Phase.SETUP_SETTLEMENT
		phase_changed.emit(current_phase)
		turn_changed.emit(current_player_index)
		log_message.emit("Game started! Player 1, place a settlement.")

# ── Phase helpers ──────────────────────────────────────────────────────────
func get_current_player() -> PlayerData:
	return players[current_player_index]

func _is_setup_phase() -> bool:
	return current_phase == Phase.SETUP_SETTLEMENT or current_phase == Phase.SETUP_ROAD

func advance_setup() -> void:
	if current_phase == Phase.SETUP_SETTLEMENT:
		current_phase = Phase.SETUP_ROAD
		phase_changed.emit(current_phase)
		return

	setup_placements += 1
	var total_turns: int = players.size() * 2

	if setup_placements >= total_turns:
		current_player_index = 0
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

	current_phase = Phase.SETUP_SETTLEMENT
	phase_changed.emit(current_phase)
	turn_changed.emit(current_player_index)

# ── Dice ───────────────────────────────────────────────────────────────────
func roll_dice() -> void:
	if current_phase != Phase.ROLL:
		return
	# Clear undo when a new turn starts (roll = start of turn)
	_undo_action.clear()
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
	_undo_action.clear()
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
	if current_phase == Phase.PRE_GAME:
		return false
	if not _is_setup_phase() and not can_afford(player_idx, "settlement"):
		return false
	if not vertex.can_place_settlement(player_idx):
		return false
	var was_setup := _is_setup_phase()
	var cost_paid := {}
	if not was_setup:
		cost_paid = (BUILD_COSTS["settlement"] as Dictionary).duplicate()
		spend(player_idx, "settlement")
	vertex.place_settlement(player_idx)
	players[player_idx].settlements += 1
	players[player_idx].victory_points += 1
	if was_setup and setup_round == 1:
		_give_setup_resources(vertex)
	resources_changed.emit(player_idx)
	log_message.emit("Player %d built a settlement" % (player_idx + 1))
	# Record undo
	_undo_action = {
		"type": "settlement",
		"node": vertex,
		"player_idx": player_idx,
		"cost": cost_paid,
		"was_setup": was_setup,
		"prev_building": 0,
		"prev_building_owner": -1,
		"vp_delta": 1,
		"settlements_delta": 1,
	}
	return true

func build_city(player_idx: int, vertex: Node) -> bool:
	if not can_afford(player_idx, "city"):
		log_message.emit("Player %d cannot afford a city" % (player_idx + 1))
		return false
	if vertex.building_owner != player_idx or vertex.building != 1:
		log_message.emit("Player %d: click one of your own settlements to upgrade" % (player_idx + 1))
		return false
	var cost_paid := (BUILD_COSTS["city"] as Dictionary).duplicate()
	spend(player_idx, "city")
	vertex.upgrade_to_city()
	players[player_idx].settlements -= 1
	players[player_idx].cities += 1
	players[player_idx].victory_points += 1
	resources_changed.emit(player_idx)
	log_message.emit("Player %d built a city" % (player_idx + 1))
	# Record undo
	_undo_action = {
		"type": "city",
		"node": vertex,
		"player_idx": player_idx,
		"cost": cost_paid,
		"was_setup": false,
		"vp_delta": 1,
		"settlements_delta": -1,
		"cities_delta": 1,
	}
	return true

func build_road(player_idx: int, edge: Node) -> bool:
	var is_free: bool = players[player_idx].free_roads > 0
	if not _is_setup_phase() and not is_free and not can_afford(player_idx, "road"):
		return false
	if not edge.can_place_road(player_idx):
		return false
	var was_setup := _is_setup_phase()
	var cost_paid := {}
	if is_free:
		players[player_idx].free_roads -= 1
		log_message.emit("Player %d used a free road (%d left)" % [player_idx + 1, players[player_idx].free_roads])
	elif not was_setup:
		cost_paid = (BUILD_COSTS["road"] as Dictionary).duplicate()
		spend(player_idx, "road")
	edge.place_road(player_idx)
	players[player_idx].roads += 1
	_update_longest_road()
	log_message.emit("Player %d built a road" % (player_idx + 1))
	# Record undo
	_undo_action = {
		"type": "road",
		"node": edge,
		"player_idx": player_idx,
		"cost": cost_paid,
		"was_setup": was_setup,
		"was_free": is_free,
		"roads_delta": 1,
	}
	return true

# ── Undo ───────────────────────────────────────────────────────────────────
func can_undo() -> bool:
	return not _undo_action.is_empty()

func undo_last_build() -> bool:
	if _undo_action.is_empty():
		return false
	var action := _undo_action
	_undo_action = {}
	var player_idx: int = action["player_idx"]
	var p := players[player_idx]

	match action["type"]:
		"settlement":
			var vertex: Node = action["node"]
			vertex.building = 0
			vertex.building_owner = -1
			vertex._refresh_visual()
			p.settlements -= 1
			p.victory_points -= 1
			# Refund cost if not setup
			if not action["was_setup"]:
				for res in action["cost"]:
					p.resources[res] = p.resources.get(res, 0) + action["cost"][res]
			# Take back setup resources if second round
			# (complex to undo; we skip setup-resource refund for simplicity)
		"city":
			var vertex: Node = action["node"]
			# Downgrade back to settlement
			vertex.building = 1
			vertex._refresh_visual()
			p.settlements += 1
			p.cities -= 1
			p.victory_points -= 1
			# Refund cost
			for res in action["cost"]:
				p.resources[res] = p.resources.get(res, 0) + action["cost"][res]
		"road":
			var edge: Node = action["node"]
			edge.road_owner = -1
			edge._refresh_visual()
			p.roads -= 1
			if action["was_free"]:
				p.free_roads += 1
			elif not action["was_setup"]:
				for res in action["cost"]:
					p.resources[res] = p.resources.get(res, 0) + action["cost"][res]
			_update_longest_road()

	resources_changed.emit(player_idx)
	log_message.emit("Player %d undid their last build." % (player_idx + 1))
	return true

# ── Dev Cards ──────────────────────────────────────────────────────────────
func buy_dev_card(player_idx: int) -> bool:
	if dev_card_deck.is_empty():
		log_message.emit("Dev card deck is empty!")
		return false
	if not can_afford(player_idx, "dev_card"):
		log_message.emit("Player %d cannot afford a dev card" % (player_idx + 1))
		return false
	spend(player_idx, "dev_card")
	var card: String = dev_card_deck.pop_back()
	if card == "victory_point":
		players[player_idx].victory_points += 1
		players[player_idx].victory_point_cards += 1
		resources_changed.emit(player_idx)
		log_message.emit("Player %d drew a Victory Point card! (%d VP total)" % [player_idx + 1, players[player_idx].victory_points])
		_check_victory()
	else:
		players[player_idx].dev_cards.append(card)
		resources_changed.emit(player_idx)
		log_message.emit("Player %d bought a dev card" % (player_idx + 1))
	return true

func play_dev_card(player_idx: int, card: String) -> bool:
	if current_phase != Phase.BUILD:
		return false
	var p := players[player_idx]
	if not p.dev_cards.has(card):
		return false
	p.dev_cards.erase(card)
	p.played_dev_cards.append(card)
	resources_changed.emit(player_idx)
	match card:
		"knight":
			p.knights_played += 1
			log_message.emit("Player %d played a Knight!" % (player_idx + 1))
			_update_largest_army()
			current_phase = Phase.MOVE_ROBBER
			phase_changed.emit(current_phase)
			robber_placement_required.emit()
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

# ── Bank Trading ───────────────────────────────────────────────────────────
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

# ── Player-to-Player Trading ───────────────────────────────────────────────
func send_trade_offer(from_idx: int, to_idx: int, give: Dictionary, receive: Dictionary) -> void:
	if current_phase != Phase.BUILD:
		return
	_trade_from_idx = from_idx
	_trade_to_idx   = to_idx
	_trade_give     = give.duplicate()
	_trade_receive  = receive.duplicate()
	var names := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	var give_str := ""
	for res in give:
		if give[res] > 0:
			give_str += "%d %s " % [give[res], names[res]]
	var recv_str := ""
	for res in receive:
		if receive[res] > 0:
			recv_str += "%d %s " % [receive[res], names[res]]
	log_message.emit("Player %d offers %sto Player %d for %s" % [from_idx + 1, give_str, to_idx + 1, recv_str])
	trade_offer_sent.emit(from_idx, to_idx, give, receive)

func accept_trade() -> void:
	if _trade_from_idx < 0 or _trade_to_idx < 0:
		return
	var giver  := players[_trade_from_idx]
	var taker  := players[_trade_to_idx]
	# Validate both sides still can afford
	for res in _trade_give:
		if giver.resources.get(res, 0) < _trade_give[res]:
			log_message.emit("Trade failed: Player %d no longer has enough resources." % (_trade_from_idx + 1))
			_clear_trade()
			trade_offer_resolved.emit()
			return
	for res in _trade_receive:
		if taker.resources.get(res, 0) < _trade_receive[res]:
			log_message.emit("Trade failed: Player %d no longer has enough resources." % (_trade_to_idx + 1))
			_clear_trade()
			trade_offer_resolved.emit()
			return
	# Execute
	for res in _trade_give:
		giver.resources[res] -= _trade_give[res]
		taker.resources[res] = taker.resources.get(res, 0) + _trade_give[res]
	for res in _trade_receive:
		taker.resources[res] -= _trade_receive[res]
		giver.resources[res] = giver.resources.get(res, 0) + _trade_receive[res]
	resources_changed.emit(_trade_from_idx)
	resources_changed.emit(_trade_to_idx)
	log_message.emit("✅ Trade accepted! Player %d and Player %d exchanged resources." % [_trade_from_idx + 1, _trade_to_idx + 1])
	_clear_trade()
	trade_offer_resolved.emit()

func decline_trade() -> void:
	log_message.emit("❌ Player %d declined the trade offer." % (_trade_to_idx + 1))
	_clear_trade()
	trade_offer_resolved.emit()

func _clear_trade() -> void:
	_trade_from_idx = -1
	_trade_to_idx   = -1
	_trade_give     = {}
	_trade_receive  = {}

# ── Robber ─────────────────────────────────────────────────────────────────
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

	var victims: Array = []
	for v in hex.vertex_nodes:
		var owner: int = v.building_owner
		if owner != -1 and owner != current_player_index and not victims.has(owner):
			var total_res := 0
			for res in ResType.values():
				total_res += players[owner].resources.get(res, 0)
			if total_res > 0:
				victims.append(owner)

	if victims.is_empty():
		current_phase = Phase.BUILD
		phase_changed.emit(current_phase)
	else:
		current_phase = Phase.BUILD
		phase_changed.emit(current_phase)
		steal_required.emit(current_player_index, victims)

func steal_from_player(thief_idx: int, victim_idx: int) -> void:
	var victim := players[victim_idx]
	var available: Array = []
	for res in ResType.values():
		for _i in victim.resources.get(res, 0):
			available.append(res)
	if available.is_empty():
		return
	var stolen_res: int = available[randi() % available.size()]
	victim.resources[stolen_res] -= 1
	players[thief_idx].resources[stolen_res] = players[thief_idx].resources.get(stolen_res, 0) + 1
	resources_changed.emit(victim_idx)
	resources_changed.emit(thief_idx)
	var names := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	log_message.emit("Player %d stole 1 %s from Player %d" % [thief_idx + 1, names[stolen_res], victim_idx + 1])

# ── Discard ────────────────────────────────────────────────────────────────
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
	var entry: Array = _discard_queue[0]
	_discard_current_idx = entry[0]
	_discard_amount = entry[1]
	_discard_queue.remove_at(0)
	current_phase = Phase.DISCARD
	phase_changed.emit(current_phase)
	discard_required.emit(_discard_current_idx, _discard_amount)

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
				var v_owner: int = v.building_owner
				var v_building: int = v.building
				if v_owner >= 0:
					var amount: int = 2 if v_building == 2 else 1
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
				return 2
			elif v.port_type == 5:
				return 3
	return 4

func _update_longest_road() -> void:
	var current_holder := -1
	for i in players.size():
		if players[i].has_longest_road:
			current_holder = i
			break
	for i in players.size():
		players[i].longest_road_length = _calculate_longest_road(i)
	var best_length := 0
	var best_player := -1
	for i in players.size():
		if players[i].longest_road_length > best_length:
			best_length = players[i].longest_road_length
			best_player = i
	if best_length < 5:
		return
	if current_holder == -1:
		players[best_player].has_longest_road = true
		players[best_player].victory_points += 2
		resources_changed.emit(best_player)
		log_message.emit("🛣️ Player %d claims Longest Road! (length %d)" % [best_player + 1, best_length])
	elif best_player != current_holder:
		if players[best_player].longest_road_length > players[current_holder].longest_road_length:
			players[current_holder].has_longest_road = false
			players[current_holder].victory_points -= 2
			resources_changed.emit(current_holder)
			log_message.emit("Player %d lost Longest Road!" % (current_holder + 1))
			players[best_player].has_longest_road = true
			players[best_player].victory_points += 2
			resources_changed.emit(best_player)
			log_message.emit("🛣️ Player %d takes Longest Road! (length %d)" % [best_player + 1, best_length])

func _update_largest_army() -> void:
	var current_holder := -1
	for i in players.size():
		if players[i].has_largest_army:
			current_holder = i
			break
	var best_knights := 0
	var best_player := -1
	for i in players.size():
		if players[i].knights_played > best_knights:
			best_knights = players[i].knights_played
			best_player = i
	if best_knights < 3:
		return
	if current_holder == -1:
		players[best_player].has_largest_army = true
		players[best_player].victory_points += 2
		resources_changed.emit(best_player)
		log_message.emit("⚔️ Player %d claims Largest Army! (%d knights)" % [best_player + 1, best_knights])
	elif best_player != current_holder:
		if players[best_player].knights_played > players[current_holder].knights_played:
			players[current_holder].has_largest_army = false
			players[current_holder].victory_points -= 2
			resources_changed.emit(current_holder)
			log_message.emit("Player %d lost Largest Army!" % (current_holder + 1))
			players[best_player].has_largest_army = true
			players[best_player].victory_points += 2
			resources_changed.emit(best_player)
			log_message.emit("⚔️ Player %d takes Largest Army! (%d knights)" % [best_player + 1, best_knights])

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
