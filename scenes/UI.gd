extends CanvasLayer

@onready var lbl_player: Label       = $Panel/VBox/LblPlayer
@onready var lbl_phase: Label        = $Panel/VBox/LblPhase
@onready var lbl_dice: Label         = $Panel/VBox/LblDice
@onready var lbl_vp: Label           = $Panel/VBox/LblVP
@onready var lbl_resources: Label    = $Panel/VBox/LblResources
@onready var btn_roll: Button        = $Panel/VBox/BtnRoll
@onready var btn_end: Button         = $Panel/VBox/BtnEnd
@onready var btn_settlement: Button  = $Panel/VBox/BtnSettlement
@onready var btn_city: Button        = $Panel/VBox/BtnCity
@onready var btn_road: Button        = $Panel/VBox/BtnRoad
@onready var btn_dev: Button         = $Panel/VBox/BtnDev
@onready var log_box: RichTextLabel  = $Panel/VBox/LogBox

# Trade UI
@onready var give_option: OptionButton    = $Panel/VBox/HBoxTrade/GiveOption
@onready var receive_option: OptionButton = $Panel/VBox/HBoxTrade/ReceiveOption
@onready var btn_trade: Button            = $Panel/VBox/HBoxTrade/BtnTrade

var _pending_action: String = ""

func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.resources_changed.connect(_on_resources_changed)
	GameManager.dice_rolled.connect(_on_dice_rolled)
	GameManager.log_message.connect(_on_log)
	GameManager.game_over.connect(_on_game_over)

	btn_roll.pressed.connect(_on_roll_pressed)
	btn_end.pressed.connect(_on_end_pressed)
	btn_settlement.pressed.connect(func(): _set_action("settlement"))
	btn_city.pressed.connect(func(): _set_action("city"))
	btn_road.pressed.connect(func(): _set_action("road"))
	btn_dev.pressed.connect(_on_buy_dev)
	btn_trade.pressed.connect(_on_trade_pressed)

	_populate_trade_options()

	for v in GameManager.vertices:
		v.clicked.connect(_on_vertex_clicked)
	for e in GameManager.edges:
		e.clicked.connect(_on_edge_clicked)

	_refresh_ui()

func _populate_trade_options() -> void:
	var labels := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	give_option.clear()
	receive_option.clear()
	for l in labels:
		give_option.add_item(l)
		receive_option.add_item(l)

# ── UI refresh ─────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	if GameManager.players.is_empty():
		return
	var p := GameManager.get_current_player()
	lbl_player.text = "Player %d" % (p.player_index + 1)
	lbl_player.add_theme_color_override("font_color", p.color)
	lbl_phase.text = "Phase: " + GameManager.Phase.keys()[GameManager.current_phase]
	lbl_vp.text = "VP: %d" % p.victory_points

	var res_labels := ["Wood", "Brick", "Ore", "Wheat", "Sheep"]
	var res_text := ""
	for i in GameManager.ResType.values().size():
		var res_val: int = GameManager.ResType.values()[i]
		res_text += "%s: %d  " % [res_labels[i], p.resources.get(res_val, 0)]
	lbl_resources.text = res_text

	var in_roll  := GameManager.current_phase == GameManager.Phase.ROLL
	var in_build := GameManager.current_phase == GameManager.Phase.BUILD
	var in_setup := GameManager._is_setup_phase()

	btn_roll.disabled       = not in_roll
	btn_end.disabled        = not in_build
	btn_settlement.disabled = not (in_build or in_setup)
	btn_city.disabled       = not in_build
	btn_road.disabled       = not (in_build or in_setup)
	btn_dev.disabled        = not in_build
	btn_trade.disabled      = not in_build

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

func _on_roll_pressed() -> void:
	GameManager.roll_dice()

func _on_end_pressed() -> void:
	GameManager.end_turn()

func _on_buy_dev() -> void:
	GameManager.buy_dev_card(GameManager.current_player_index)

func _on_trade_pressed() -> void:
	var give: int    = give_option.selected
	var receive: int = receive_option.selected
	if give != receive:
		GameManager.bank_trade(GameManager.current_player_index, give, receive)

func _set_action(action: String) -> void:
	_pending_action = action

func _on_vertex_clicked(v: Node) -> void:
	var idx := GameManager.current_player_index
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
	var idx := GameManager.current_player_index
	if _pending_action == "road":
		if GameManager.build_road(idx, e):
			if GameManager._is_setup_phase():
				GameManager.advance_setup()
			_pending_action = ""
