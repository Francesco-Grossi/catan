extends CanvasLayer

# ── Sidebar refs ───────────────────────────────────────────────────────────
@onready var lbl_player:       Label        = $Panel/VBox/LblPlayer
@onready var lbl_phase:        Label        = $Panel/VBox/LblPhase
@onready var lbl_dice:         Label        = $Panel/VBox/LblDice
@onready var lbl_vp:           Label        = $Panel/VBox/LblVP
@onready var lbl_resources:    Label        = $Panel/VBox/LblResources
@onready var lbl_robber:       Label        = $Panel/VBox/LblRobber

# Pre-game section (lives inside the sidebar VBox)
@onready var pregame_section:  VBoxContainer = $Panel/VBox/PreGameSection
@onready var btn_shuffle:      Button        = $Panel/VBox/PreGameSection/BtnShuffle
@onready var btn_start:        Button        = $Panel/VBox/PreGameSection/BtnStart

# Game section (lives inside the sidebar VBox, hidden during PRE_GAME)
@onready var game_section:     VBoxContainer = $Panel/VBox/GameSection
@onready var btn_roll:         Button        = $Panel/VBox/GameSection/BtnRoll
@onready var btn_end:          Button        = $Panel/VBox/GameSection/BtnEnd
@onready var btn_undo:         Button        = $Panel/VBox/GameSection/BtnUndo
@onready var btn_settlement:   Button        = $Panel/VBox/GameSection/BtnSettlement
@onready var btn_city:         Button        = $Panel/VBox/GameSection/BtnCity
@onready var btn_road:         Button        = $Panel/VBox/GameSection/BtnRoad
@onready var btn_dev:          Button        = $Panel/VBox/GameSection/BtnDev
@onready var btn_view_dev:     Button        = $Panel/VBox/GameSection/BtnViewDev
@onready var btn_view_played:  Button        = $Panel/VBox/GameSection/BtnViewPlayed
@onready var btn_view_stats:   Button        = $Panel/VBox/GameSection/BtnViewStats
@onready var hbox_bank_trade:  HBoxContainer = $Panel/VBox/GameSection/HBoxBankTrade
@onready var give_option:      OptionButton  = $Panel/VBox/GameSection/HBoxBankTrade/GiveOption
@onready var receive_option:   OptionButton  = $Panel/VBox/GameSection/HBoxBankTrade/ReceiveOption
@onready var btn_bank_trade:   Button        = $Panel/VBox/GameSection/HBoxBankTrade/BtnBankTrade
@onready var btn_player_trade: Button        = $Panel/VBox/GameSection/BtnPlayerTrade

@onready var log_box: RichTextLabel = $Panel/VBox/LogBox

# ── Floating panels ────────────────────────────────────────────────────────
@onready var dev_panel:           Panel         = $DevPanel
@onready var dev_list:            VBoxContainer = $DevPanel/VBox/CardList
@onready var btn_close_dev:       Button        = $DevPanel/VBox/BtnClose

@onready var played_panel:        Panel         = $PlayedPanel
@onready var played_list:         VBoxContainer = $PlayedPanel/VBox/PlayedList
@onready var btn_close_played:    Button        = $PlayedPanel/VBox/BtnClose

@onready var stats_panel:         Panel         = $StatsPanel
@onready var stats_list:          VBoxContainer = $StatsPanel/VBox/StatsList
@onready var btn_close_stats:     Button        = $StatsPanel/VBox/BtnClose

@onready var discard_panel:       Panel         = $DiscardPanel
@onready var discard_label:       Label         = $DiscardPanel/VBox/LblDiscard
@onready var discard_list:        VBoxContainer = $DiscardPanel/VBox/DiscardList
@onready var btn_confirm_discard: Button        = $DiscardPanel/VBox/BtnConfirm

@onready var yop_panel:  Panel        = $YopPanel
@onready var yop_res1:   OptionButton = $YopPanel/VBox/HBox1/Res1
@onready var yop_res2:   OptionButton = $YopPanel/VBox/HBox2/Res2
@onready var btn_yop_ok: Button       = $YopPanel/VBox/BtnOk

@onready var mono_panel:  Panel        = $MonoPanel
@onready var mono_res:    OptionButton = $MonoPanel/VBox/MonoRes
@onready var btn_mono_ok: Button       = $MonoPanel/VBox/BtnOk

@onready var steal_panel:  Panel         = $StealPanel
@onready var steal_label:  Label         = $StealPanel/VBox/LblSteal
@onready var steal_list:   VBoxContainer = $StealPanel/VBox/StealList

@onready var pt_panel:      Panel         = $PtPanel
@onready var pt_target:     OptionButton  = $PtPanel/VBox/HBoxTarget/TargetOption
@onready var pt_give_list:  VBoxContainer = $PtPanel/VBox/GiveList
@onready var pt_recv_list:  VBoxContainer = $PtPanel/VBox/RecvList
@onready var btn_pt_send:   Button        = $PtPanel/VBox/BtnSend
@onready var btn_pt_cancel: Button        = $PtPanel/VBox/BtnCancel

@onready var tr_panel:      Panel  = $TrPanel
@onready var tr_label:      Label  = $TrPanel/VBox/LblOffer
@onready var btn_tr_accept: Button = $TrPanel/VBox/BtnAccept
@onready var btn_tr_decline:Button = $TrPanel/VBox/BtnDecline

# ── State ──────────────────────────────────────────────────────────────────
var _pending_action: String = ""
var _discard_spins:  Dictionary = {}
var _pt_give_spins:  Dictionary = {}
var _pt_recv_spins:  Dictionary = {}
var _board: Node2D = null

func _ready() -> void:
	_board = get_node_or_null("/root/Main/Board")

	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.turn_changed.connect(func(_i): _refresh_ui())
	GameManager.resources_changed.connect(func(_i): _refresh_ui())
	GameManager.dice_rolled.connect(func(d1, d2, t): lbl_dice.text = "🎲 %d+%d=%d" % [d1, d2, t])
	GameManager.log_message.connect(func(m): log_box.append_text(m + "\n"))
	GameManager.game_over.connect(_on_game_over)
	GameManager.discard_required.connect(_on_discard_required)
	GameManager.robber_placement_required.connect(func(): lbl_robber.visible = true)
	GameManager.steal_required.connect(_on_steal_required)
	GameManager.trade_offer_sent.connect(_on_trade_offer_sent)
	GameManager.trade_offer_resolved.connect(func(): tr_panel.visible = false)

	btn_shuffle.pressed.connect(_on_shuffle)
	btn_start.pressed.connect(_on_start)

	btn_roll.pressed.connect(func(): GameManager.roll_dice())
	btn_end.pressed.connect(func(): GameManager.end_turn())
	btn_undo.pressed.connect(func(): GameManager.undo_last_build(); _refresh_ui())
	btn_settlement.pressed.connect(func(): _set_action("settlement"))
	btn_city.pressed.connect(func(): _set_action("city"))
	btn_road.pressed.connect(func(): _set_action("road"))
	btn_dev.pressed.connect(_on_buy_dev)
	btn_view_dev.pressed.connect(_open_dev_panel)
	btn_view_played.pressed.connect(_open_played_panel)
	btn_view_stats.pressed.connect(_open_stats_panel)
	btn_bank_trade.pressed.connect(_on_bank_trade)
	btn_player_trade.pressed.connect(_open_pt_panel)

	btn_close_dev.pressed.connect(func(): dev_panel.visible = false)
	btn_close_played.pressed.connect(func(): played_panel.visible = false)
	btn_close_stats.pressed.connect(func(): stats_panel.visible = false)
	btn_confirm_discard.pressed.connect(_on_confirm_discard)
	btn_yop_ok.pressed.connect(_on_yop_ok)
	btn_mono_ok.pressed.connect(_on_mono_ok)
	btn_pt_send.pressed.connect(_on_pt_send)
	btn_pt_cancel.pressed.connect(func(): pt_panel.visible = false)
	btn_tr_accept.pressed.connect(func(): GameManager.accept_trade())
	btn_tr_decline.pressed.connect(func(): GameManager.decline_trade())

	var res_labels := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	for opt in [give_option, receive_option, yop_res1, yop_res2, mono_res]:
		opt.clear()
		for l in res_labels:
			opt.add_item(l)

	_build_pt_spins()

	for pan in [dev_panel, played_panel, stats_panel, discard_panel, yop_panel,
				mono_panel, steal_panel, pt_panel, tr_panel]:
		pan.visible = false
	lbl_robber.visible = false

	for v in GameManager.vertices:
		v.clicked.connect(_on_vertex_clicked)
	for e in GameManager.edges:
		e.clicked.connect(_on_edge_clicked)

	_on_phase_changed(GameManager.current_phase)

# ── Phase change ───────────────────────────────────────────────────────────
func _on_phase_changed(phase: int) -> void:
	var in_pregame := (phase == GameManager.Phase.PRE_GAME)
	pregame_section.visible = in_pregame
	game_section.visible    = not in_pregame
	_refresh_ui()

# ── UI refresh ─────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	if GameManager.players.is_empty():
		return
	var p  := GameManager.get_current_player()
	var ph := GameManager.current_phase
	var P  := GameManager.Phase

	lbl_player.text = "Player %d" % (p.player_index + 1)
	lbl_player.add_theme_color_override("font_color", p.color)

	var pnames := ["PRE-GAME","SETUP_SETTLEMENT","SETUP_ROAD","ROLL",
				   "BUILD","MOVE_ROBBER","DISCARD","END_TURN"]
	lbl_phase.text = "Phase: " + (pnames[ph] if ph < pnames.size() else "")

	var vp := "VP: %d" % p.victory_points
	if p.has_longest_road: vp += " 🛣️"
	if p.has_largest_army: vp += " ⚔️"
	lbl_vp.text = vp

	var rl := ["Wd","Br","Or","Wh","Sh"]
	var rt := ""
	for i in GameManager.ResType.values().size():
		rt += "%s:%d  " % [rl[i], p.resources.get(GameManager.ResType.values()[i], 0)]
	lbl_resources.text = rt

	if not game_section.visible:
		return

	var in_roll    := ph == P.ROLL
	var in_build   := ph == P.BUILD
	var in_setup_s := ph == P.SETUP_SETTLEMENT
	var in_setup_r := ph == P.SETUP_ROAD
	var in_setup   := in_setup_s or in_setup_r

	btn_roll.visible         = in_roll
	btn_end.visible          = in_build
	btn_undo.visible         = in_build or in_setup
	btn_settlement.visible   = in_build or in_setup_s
	btn_city.visible         = in_build
	btn_road.visible         = in_build or in_setup_r
	btn_dev.visible          = in_build
	hbox_bank_trade.visible  = in_build
	btn_player_trade.visible = in_build

	btn_roll.disabled         = not in_roll
	btn_end.disabled          = not in_build
	btn_undo.disabled         = not GameManager.can_undo()
	btn_settlement.disabled   = not (in_build or in_setup_s)
	btn_city.disabled         = not in_build
	btn_road.disabled         = not (in_build or in_setup_r)
	btn_dev.disabled          = not in_build
	btn_bank_trade.disabled   = not in_build
	btn_player_trade.disabled = not in_build

	btn_dev.text      = "🃏 Buy Dev (%d)" % GameManager.dev_card_deck.size()
	btn_view_dev.text = "📋 Dev Cards (%d)" % p.dev_cards.size()

	if in_setup_s:
		_pending_action = "settlement"
	elif in_setup_r:
		_pending_action = "road"
	elif not in_setup and (_pending_action == "settlement" or _pending_action == "road"):
		_pending_action = ""

	lbl_robber.visible = (ph == P.MOVE_ROBBER)

# ── Pre-game ───────────────────────────────────────────────────────────────
func _on_start() -> void:
	GameManager.start_game()

func _on_shuffle() -> void:
	if _board == null:
		_board = get_node_or_null("/root/Main/Board")
	if _board and _board.has_method("_generate_board"):
		_board._generate_board()
		GameManager.log_message.emit("Board reshuffled.")

# ── Dev card panel ─────────────────────────────────────────────────────────
func _open_dev_panel() -> void:
	for c in dev_list.get_children():
		c.queue_free()
	var p := GameManager.get_current_player()
	if p.dev_cards.is_empty():
		var l := Label.new()
		l.text = "(no cards in hand)"
		dev_list.add_child(l)
	else:
		var counts := {}
		for card in p.dev_cards:
			counts[card] = counts.get(card, 0) + 1
		var cnames := {
			"knight":         "⚔️ Knight",
			"road_building":  "🛤️ Road Building",
			"year_of_plenty": "🌟 Year of Plenty",
			"monopoly":       "💰 Monopoly",
		}
		for card in counts:
			var hb := HBoxContainer.new()
			var lb := Label.new()
			lb.text = "%s ×%d" % [cnames.get(card, card), counts[card]]
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(lb)
			if GameManager.current_phase == GameManager.Phase.BUILD:
				var btn := Button.new()
				btn.text = "▶ Play"
				var cc: String = card
				btn.pressed.connect(func(): _play_dev(cc))
				hb.add_child(btn)
			dev_list.add_child(hb)
	dev_panel.visible = true

func _play_dev(card: String) -> void:
	dev_panel.visible = false
	var idx := GameManager.current_player_index
	match card:
		"year_of_plenty": yop_panel.visible = true
		"monopoly":       mono_panel.visible = true
		_:
			GameManager.play_dev_card(idx, card)
			_refresh_ui()

func _open_played_panel() -> void:
	for c in played_list.get_children():
		c.queue_free()
	var cnames := {
		"knight":         "⚔️ Knight",
		"road_building":  "🛤️ Road Building",
		"year_of_plenty": "🌟 Year of Plenty",
		"monopoly":       "💰 Monopoly",
	}
	var any_found := false
	for i in GameManager.players.size():
		var pl := GameManager.players[i]
		if pl.played_dev_cards.is_empty() and pl.victory_point_cards == 0:
			continue
		any_found = true
		var h := Label.new()
		h.text = "── Player %d ──" % (i + 1)
		h.add_theme_color_override("font_color", pl.color)
		played_list.add_child(h)
		var counts := {}
		for card in pl.played_dev_cards:
			counts[card] = counts.get(card, 0) + 1
		if pl.victory_point_cards > 0:
			counts["victory_point"] = pl.victory_point_cards
		for card in counts:
			var lb := Label.new()
			var lname: String = "🏆 Victory Point" if card == "victory_point" else cnames.get(card, card)
			lb.text = "  %s ×%d" % [lname, counts[card]]
			played_list.add_child(lb)
	if not any_found:
		var lb := Label.new()
		lb.text = "(none yet)"
		played_list.add_child(lb)
	played_panel.visible = true

# ── Player Stats panel ─────────────────────────────────────────────────────
func _open_stats_panel() -> void:
	for c in stats_list.get_children():
		c.queue_free()

	for i in GameManager.players.size():
		var pl := GameManager.players[i]

		# Player header (coloured)
		var header := Label.new()
		header.text = "── Player %d ──" % (i + 1)
		header.add_theme_color_override("font_color", pl.color)
		stats_list.add_child(header)

		# Total resources (sum of all types)
		var total_res := 0
		for res in pl.resources.values():
			total_res += res
		var res_lbl := Label.new()
		res_lbl.text = "  🗃 Resources: %d" % total_res
		stats_list.add_child(res_lbl)

		# Total unplayed dev cards in hand
		# dev_cards holds regular cards; victory_point_cards are scored immediately
		# but we show them here as "unplayed" because the player still holds them
		var total_dev := pl.dev_cards.size() + pl.victory_point_cards
		var dev_lbl := Label.new()
		dev_lbl.text = "  🃏 Dev cards (unplayed): %d" % total_dev
		stats_list.add_child(dev_lbl)

		# Separator between players (not after last)
		if i < GameManager.players.size() - 1:
			var sep := HSeparator.new()
			stats_list.add_child(sep)

	stats_panel.visible = true

# ── Discard ────────────────────────────────────────────────────────────────
func _on_discard_required(player_idx: int, amount: int) -> void:
	var p := GameManager.players[player_idx]
	discard_label.text = "Player %d: discard %d" % [player_idx + 1, amount]
	discard_label.add_theme_color_override("font_color", p.color)
	_discard_spins.clear()
	for c in discard_list.get_children():
		c.queue_free()
	var rl := ["Wood","Brick","Ore","Wheat","Sheep"]
	for i in GameManager.ResType.values().size():
		var res: int = GameManager.ResType.values()[i]
		var owned: int = p.resources.get(res, 0)
		if owned == 0:
			continue
		var hb := HBoxContainer.new()
		var lb := Label.new()
		lb.text = "%s (%d):" % [rl[i], owned]
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(lb)
		var sp := SpinBox.new()
		sp.min_value = 0
		sp.max_value = owned
		sp.step = 1
		sp.custom_minimum_size = Vector2(70, 0)
		_discard_spins[res] = sp
		hb.add_child(sp)
		discard_list.add_child(hb)
	btn_confirm_discard.text = "Confirm (need %d)" % amount
	discard_panel.visible = true

func _on_confirm_discard() -> void:
	var chosen := {}
	for res in _discard_spins:
		var v := int((_discard_spins[res] as SpinBox).value)
		if v > 0:
			chosen[res] = v
	GameManager.submit_discard(GameManager._discard_current_idx, chosen)
	if GameManager.current_phase != GameManager.Phase.DISCARD:
		discard_panel.visible = false

# ── Year of Plenty / Monopoly ──────────────────────────────────────────────
func _on_yop_ok() -> void:
	var idx := GameManager.current_player_index
	GameManager.play_dev_card(idx, "year_of_plenty")
	GameManager.play_year_of_plenty(idx, yop_res1.selected, yop_res2.selected)
	yop_panel.visible = false
	_refresh_ui()

func _on_mono_ok() -> void:
	var idx := GameManager.current_player_index
	GameManager.play_dev_card(idx, "monopoly")
	GameManager.play_monopoly(idx, mono_res.selected)
	mono_panel.visible = false
	_refresh_ui()

# ── Bank trade ─────────────────────────────────────────────────────────────
func _on_bank_trade() -> void:
	var give := give_option.selected
	var recv := receive_option.selected
	if give != recv:
		GameManager.bank_trade(GameManager.current_player_index, give, recv)

func _on_buy_dev() -> void:
	if GameManager.buy_dev_card(GameManager.current_player_index):
		_open_dev_panel()
	_refresh_ui()

# ── Player trade ───────────────────────────────────────────────────────────
func _build_pt_spins() -> void:
	for c in pt_give_list.get_children(): c.queue_free()
	for c in pt_recv_list.get_children(): c.queue_free()
	_pt_give_spins.clear()
	_pt_recv_spins.clear()
	var rl := ["Wood","Brick","Ore","Wheat","Sheep"]
	var rt := GameManager.ResType.values()
	for i in rt.size():
		var res: int = rt[i]
		for pass_give in [true, false]:
			var hb := HBoxContainer.new()
			var lb := Label.new()
			lb.text = rl[i] + ":"
			lb.custom_minimum_size = Vector2(50, 0)
			hb.add_child(lb)
			var sp := SpinBox.new()
			sp.min_value = 0
			sp.max_value = 3
			sp.step = 1
			sp.custom_minimum_size = Vector2(60, 0)
			hb.add_child(sp)
			if pass_give:
				_pt_give_spins[res] = sp
				pt_give_list.add_child(hb)
			else:
				_pt_recv_spins[res] = sp
				pt_recv_list.add_child(hb)

func _open_pt_panel() -> void:
	pt_target.clear()
	for i in GameManager.players.size():
		if i == GameManager.current_player_index:
			continue
		pt_target.add_item("Player %d" % (i + 1), i)
	for res in _pt_give_spins: (_pt_give_spins[res] as SpinBox).value = 0
	for res in _pt_recv_spins: (_pt_recv_spins[res] as SpinBox).value = 0
	pt_panel.visible = true

func _on_pt_send() -> void:
	if pt_target.item_count == 0:
		return
	var to_idx   := pt_target.get_item_id(pt_target.selected)
	var from_idx := GameManager.current_player_index
	var give := {}
	var recv := {}
	var give_total := 0
	var recv_total := 0
	for res in _pt_give_spins:
		var v := int((_pt_give_spins[res] as SpinBox).value)
		if v > 0:
			give[res] = v
			give_total += v
	for res in _pt_recv_spins:
		var v := int((_pt_recv_spins[res] as SpinBox).value)
		if v > 0:
			recv[res] = v
			recv_total += v
	if give_total == 0 or recv_total == 0:
		GameManager.log_message.emit("Both sides must include at least 1 resource.")
		return
	var sender := GameManager.players[from_idx]
	for res in give:
		if sender.resources.get(res, 0) < give[res]:
			GameManager.log_message.emit("You don't have enough resources for this offer.")
			return
	pt_panel.visible = false
	GameManager.send_trade_offer(from_idx, to_idx, give, recv)

func _on_trade_offer_sent(from_idx: int, to_idx: int, give: Dictionary, receive: Dictionary) -> void:
	var rl := ["Wood","Brick","Ore","Wheat","Sheep"]
	var gs := ""; var rs := ""
	for res in give:
		if give[res] > 0:
			gs += "%d %s  " % [give[res], rl[res]]
	for res in receive:
		if receive[res] > 0:
			rs += "%d %s  " % [receive[res], rl[res]]
	tr_label.text = "Player %d offers:\nGives you: %s\nWants: %s\n\nPlayer %d, accept?" % \
		[from_idx + 1, gs, rs, to_idx + 1]
	tr_panel.visible = true

# ── Steal ──────────────────────────────────────────────────────────────────
func _on_steal_required(thief_idx: int, victim_indices: Array) -> void:
	steal_label.text = "Player %d: steal from:" % (thief_idx + 1)
	for c in steal_list.get_children():
		c.queue_free()
	for victim_idx in victim_indices:
		var pl := GameManager.players[victim_idx]
		var btn := Button.new()
		btn.text = "Player %d" % (victim_idx + 1)
		btn.add_theme_color_override("font_color", pl.color)
		var cap: int = victim_idx
		btn.pressed.connect(func():
			steal_panel.visible = false
			GameManager.steal_from_player(thief_idx, cap))
		steal_list.add_child(btn)
	steal_panel.visible = true

# ── Board clicks ───────────────────────────────────────────────────────────
func _on_vertex_clicked(v: Node) -> void:
	var idx := GameManager.current_player_index
	match _pending_action:
		"settlement":
			if GameManager.build_settlement(idx, v):
				if GameManager._is_setup_phase():
					GameManager.advance_setup()
				_pending_action = ""
				_refresh_ui()
		"city":
			if GameManager.build_city(idx, v):
				_pending_action = ""
				_refresh_ui()

func _on_edge_clicked(e: Node) -> void:
	if _pending_action == "road":
		if GameManager.build_road(GameManager.current_player_index, e):
			if GameManager._is_setup_phase():
				GameManager.advance_setup()
			_pending_action = ""
			_refresh_ui()

# ── Misc ───────────────────────────────────────────────────────────────────
func _set_action(action: String) -> void:
	_pending_action = action

func _on_game_over(winner: int) -> void:
	lbl_phase.text = "🏆 Player %d WINS!" % (winner + 1)
	if game_section.visible:
		btn_roll.disabled = true
		btn_end.disabled  = true
