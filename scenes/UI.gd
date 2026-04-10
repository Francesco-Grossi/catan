extends CanvasLayer

# ── Main sidebar refs ──────────────────────────────────────────────────────
@onready var lbl_player: Label        = $Panel/VBox/LblPlayer
@onready var lbl_phase: Label         = $Panel/VBox/LblPhase
@onready var lbl_dice: Label          = $Panel/VBox/LblDice
@onready var lbl_vp: Label            = $Panel/VBox/LblVP
@onready var lbl_resources: Label     = $Panel/VBox/LblResources
@onready var lbl_robber_prompt: Label = $Panel/VBox/LblRobberPrompt
@onready var btn_roll: Button         = $Panel/VBox/BtnRoll
@onready var btn_end: Button          = $Panel/VBox/BtnEnd
@onready var btn_settlement: Button   = $Panel/VBox/BtnSettlement
@onready var btn_city: Button         = $Panel/VBox/BtnCity
@onready var btn_road: Button         = $Panel/VBox/BtnRoad
@onready var btn_dev: Button          = $Panel/VBox/BtnDev
@onready var btn_view_dev_cards: Button = $Panel/VBox/BtnViewDevCards
@onready var log_box: RichTextLabel   = $Panel/VBox/LogBox

# Trade UI
@onready var give_option: OptionButton    = $Panel/VBox/HBoxTrade/GiveOption
@onready var receive_option: OptionButton = $Panel/VBox/HBoxTrade/ReceiveOption
@onready var btn_trade: Button            = $Panel/VBox/HBoxTrade/BtnTrade

# Dev card panel
@onready var dev_card_panel: Panel        = $DevCardPanel
@onready var dev_card_list: VBoxContainer = $DevCardPanel/VBox/CardList
@onready var btn_close_dev: Button        = $DevCardPanel/VBox/BtnClose

# Discard panel
@onready var discard_panel: Panel         = $DiscardPanel
@onready var discard_label: Label         = $DiscardPanel/VBox/LblDiscard
@onready var discard_list: VBoxContainer  = $DiscardPanel/VBox/DiscardList
@onready var btn_confirm_discard: Button  = $DiscardPanel/VBox/BtnConfirmDiscard

# Year of Plenty panel
@onready var yop_panel: Panel         = $YopPanel
@onready var yop_res1: OptionButton   = $YopPanel/VBox/HBox1/Res1
@onready var yop_res2: OptionButton   = $YopPanel/VBox/HBox2/Res2
@onready var btn_yop_confirm: Button  = $YopPanel/VBox/BtnConfirm

# Monopoly panel
@onready var monopoly_panel: Panel         = $MonopolyPanel
@onready var monopoly_res: OptionButton    = $MonopolyPanel/VBox/MonopolyRes
@onready var btn_monopoly_confirm: Button  = $MonopolyPanel/VBox/BtnConfirm

# Steal panel
@onready var steal_panel: Panel            = $StealPanel
@onready var steal_label: Label            = $StealPanel/VBox/LblSteal
@onready var steal_list: VBoxContainer     = $StealPanel/VBox/StealList

var _pending_action: String = ""
var _discard_selections: Dictionary = {}   # ResType → SpinBox

func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.resources_changed.connect(_on_resources_changed)
	GameManager.dice_rolled.connect(_on_dice_rolled)
	GameManager.log_message.connect(_on_log)
	GameManager.game_over.connect(_on_game_over)
	GameManager.discard_required.connect(_on_discard_required)
	GameManager.robber_placement_required.connect(_on_robber_placement_required)
	GameManager.steal_required.connect(_on_steal_required)

	btn_roll.pressed.connect(_on_roll_pressed)
	btn_end.pressed.connect(_on_end_pressed)
	btn_settlement.pressed.connect(func(): _set_action("settlement"))
	btn_city.pressed.connect(func(): _set_action("city"))
	btn_road.pressed.connect(func(): _set_action("road"))
	btn_dev.pressed.connect(_on_buy_dev)
	btn_view_dev_cards.pressed.connect(_open_dev_card_panel)
	btn_trade.pressed.connect(_on_trade_pressed)
	btn_close_dev.pressed.connect(func(): dev_card_panel.visible = false)
	btn_confirm_discard.pressed.connect(_on_confirm_discard)
	btn_yop_confirm.pressed.connect(_on_yop_confirm)
	btn_monopoly_confirm.pressed.connect(_on_monopoly_confirm)

	_populate_trade_options()
	_populate_res_options([yop_res1, yop_res2, monopoly_res])

	dev_card_panel.visible = false
	discard_panel.visible = false
	yop_panel.visible = false
	monopoly_panel.visible = false
	steal_panel.visible = false
	lbl_robber_prompt.visible = false

	for v in GameManager.vertices:
		v.clicked.connect(_on_vertex_clicked)
	for e in GameManager.edges:
		e.clicked.connect(_on_edge_clicked)

	_refresh_ui()

# ── Option population ──────────────────────────────────────────────────────
func _populate_trade_options() -> void:
	var labels := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	give_option.clear()
	receive_option.clear()
	for l in labels:
		give_option.add_item(l)
		receive_option.add_item(l)

func _populate_res_options(opts: Array) -> void:
	var labels := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	for opt in opts:
		opt.clear()
		for l in labels:
			opt.add_item(l)

# ── UI refresh ─────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	if GameManager.players.is_empty():
		return
	var p := GameManager.get_current_player()
	lbl_player.text = "Player %d" % (p.player_index + 1)
	lbl_player.add_theme_color_override("font_color", p.color)

	var phase_names := ["SETUP_SETTLEMENT", "SETUP_ROAD", "ROLL", "BUILD",
						"MOVE_ROBBER", "DISCARD", "END_TURN"]
	lbl_phase.text = "Phase: " + phase_names[GameManager.current_phase]

	var vp_text := "VP: %d" % p.victory_points
	if p.has_longest_road: vp_text += " 🛣️"
	if p.has_largest_army: vp_text += " ⚔️"
	lbl_vp.text = vp_text

	var res_labels := ["Wd", "Br", "Or", "Wh", "Sh"]
	var res_text := ""
	for i in GameManager.ResType.values().size():
		var res_val: int = GameManager.ResType.values()[i]
		res_text += "%s:%d  " % [res_labels[i], p.resources.get(res_val, 0)]
	lbl_resources.text = res_text

	btn_dev.text = "🃏 Buy Dev (%d)" % GameManager.dev_card_deck.size()
	btn_view_dev_cards.text = "📋 Dev Cards (%d)" % p.dev_cards.size()

	var in_roll  : bool = GameManager.current_phase == GameManager.Phase.ROLL
	var in_build : bool = GameManager.current_phase == GameManager.Phase.BUILD
	var in_setup : bool = GameManager._is_setup_phase()
	var in_robber: bool = GameManager.current_phase == GameManager.Phase.MOVE_ROBBER

	btn_roll.disabled       = not in_roll
	btn_end.disabled        = not in_build
	btn_settlement.disabled = not (in_build or in_setup)
	btn_city.disabled       = not in_build
	btn_road.disabled       = not (in_build or in_setup)
	btn_dev.disabled        = not in_build
	btn_trade.disabled      = not in_build

	lbl_robber_prompt.visible = in_robber

# ── Dev card panel ─────────────────────────────────────────────────────────
func _open_dev_card_panel() -> void:
	_refresh_dev_cards()
	dev_card_panel.visible = true

func _refresh_dev_cards() -> void:
	for child in dev_card_list.get_children():
		child.queue_free()

	var p := GameManager.get_current_player()
	if p.dev_cards.is_empty():
		var lbl := Label.new()
		lbl.text = "(no dev cards in hand)"
		dev_card_list.add_child(lbl)
		return

	var counts: Dictionary = {}
	for card in p.dev_cards:
		counts[card] = counts.get(card, 0) + 1

	var card_labels: Dictionary = {
		"knight":         "⚔️ Knight",
		"victory_point":  "🏆 Victory Point",
		"road_building":  "🛤️ Road Building",
		"year_of_plenty": "🌟 Year of Plenty",
		"monopoly":       "💰 Monopoly",
	}

	for card in counts:
		var hbox := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s ×%d" % [card_labels.get(card, card), counts[card]]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(lbl)

		if card != "victory_point" and GameManager.current_phase == GameManager.Phase.BUILD:
			var btn := Button.new()
			btn.text = "▶ Play"
			var captured_card: String = card
			btn.pressed.connect(func(): _play_dev_card(captured_card))
			hbox.add_child(btn)

		dev_card_list.add_child(hbox)

func _play_dev_card(card: String) -> void:
	dev_card_panel.visible = false
	var idx: int = GameManager.current_player_index
	match card:
		"year_of_plenty":
			yop_panel.visible = true
		"monopoly":
			monopoly_panel.visible = true
		_:
			GameManager.play_dev_card(idx, card)
			_refresh_ui()

# ── Signal handlers ────────────────────────────────────────────────────────
func _on_phase_changed(_p: int) -> void:
	_refresh_ui()

func _on_turn_changed(_i: int) -> void:
	_refresh_ui()

func _on_resources_changed(_i: int) -> void:
	_refresh_ui()

func _on_dice_rolled(d1: int, d2: int, total: int) -> void:
	lbl_dice.text = "🎲 %d + %d = %d" % [d1, d2, total]

func _on_log(msg: String) -> void:
	log_box.append_text(msg + "\n")

func _on_game_over(winner: int) -> void:
	lbl_phase.text = "🏆 Player %d WINS!" % (winner + 1)
	btn_roll.disabled = true
	btn_end.disabled  = true

func _on_discard_required(player_idx: int, amount: int) -> void:
	var p := GameManager.players[player_idx]
	discard_label.text = "Player %d: discard %d resources" % [player_idx + 1, amount]
	discard_label.add_theme_color_override("font_color", p.color)
	_discard_selections.clear()

	for child in discard_list.get_children():
		child.queue_free()

	var res_labels := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	var res_types := GameManager.ResType.values()

	for i in res_types.size():
		var res: int = res_types[i]
		var owned: int = p.resources.get(res, 0)
		if owned == 0:
			continue
		var hbox := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s (have %d):" % [res_labels[i], owned]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(lbl)

		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = owned
		spin.value = 0
		spin.step = 1
		spin.custom_minimum_size = Vector2(70, 0)
		_discard_selections[res] = spin
		hbox.add_child(spin)
		discard_list.add_child(hbox)

	btn_confirm_discard.text = "Confirm (need %d)" % amount
	discard_panel.visible = true

func _on_confirm_discard() -> void:
	var chosen: Dictionary = {}
	for res in _discard_selections:
		var val: int = int((_discard_selections[res] as SpinBox).value)
		if val > 0:
			chosen[res] = val
	GameManager.submit_discard(GameManager._discard_current_idx, chosen)
	if GameManager.current_phase != GameManager.Phase.DISCARD:
		discard_panel.visible = false

func _on_robber_placement_required() -> void:
	lbl_robber_prompt.visible = true

func _on_roll_pressed() -> void:
	GameManager.roll_dice()

func _on_end_pressed() -> void:
	GameManager.end_turn()

func _on_buy_dev() -> void:
	if GameManager.buy_dev_card(GameManager.current_player_index):
		_open_dev_card_panel()
	_refresh_ui()

func _on_trade_pressed() -> void:
	var give: int    = give_option.selected
	var receive: int = receive_option.selected
	if give != receive:
		GameManager.bank_trade(GameManager.current_player_index, give, receive)

func _on_yop_confirm() -> void:
	var idx: int = GameManager.current_player_index
	GameManager.play_dev_card(idx, "year_of_plenty")
	GameManager.play_year_of_plenty(idx, yop_res1.selected, yop_res2.selected)
	yop_panel.visible = false
	_refresh_ui()

func _on_monopoly_confirm() -> void:
	var idx: int = GameManager.current_player_index
	GameManager.play_dev_card(idx, "monopoly")
	GameManager.play_monopoly(idx, monopoly_res.selected)
	monopoly_panel.visible = false
	_refresh_ui()

func _set_action(action: String) -> void:
	_pending_action = action

func _on_vertex_clicked(v: Node) -> void:
	var idx: int = GameManager.current_player_index
	match _pending_action:
		"settlement":
			if GameManager.build_settlement(idx, v):
				if GameManager._is_setup_phase():
					GameManager.advance_setup()
				_pending_action = ""
		"city":
			if GameManager.build_city(idx, v):
				_pending_action = ""

func _on_edge_clicked(e: Node) -> void:
	var idx: int = GameManager.current_player_index
	if _pending_action == "road":
		if GameManager.build_road(idx, e):
			if GameManager._is_setup_phase():
				GameManager.advance_setup()
			_pending_action = ""

func _on_steal_required(thief_idx: int, victim_indices: Array) -> void:
	steal_label.text = "Player %d: choose a player to steal from" % (thief_idx + 1)
	# Clear previous buttons
	for child in steal_list.get_children():
		child.queue_free()
	# One button per eligible victim
	for victim_idx in victim_indices:
		var p := GameManager.players[victim_idx]
		var btn := Button.new()
		btn.text = "Player %d" % (victim_idx + 1)
		btn.add_theme_color_override("font_color", p.color)
		var captured: int = victim_idx
		btn.pressed.connect(func():
			steal_panel.visible = false
			GameManager.steal_from_player(thief_idx, captured)
		)
		steal_list.add_child(btn)
	steal_panel.visible = true
