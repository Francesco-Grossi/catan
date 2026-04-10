extends Node2D

const TERRAIN_COLORS: Dictionary = {
	0: Color(0.13, 0.55, 0.13),  # WOOD
	1: Color(0.78, 0.31, 0.08),  # BRICK
	2: Color(0.55, 0.55, 0.55),  # ORE
	3: Color(0.93, 0.83, 0.10),  # WHEAT
	4: Color(0.56, 0.93, 0.56),  # SHEEP
	5: Color(0.87, 0.80, 0.55),  # DESERT
}

const TERRAIN_LABELS: Dictionary = {
	0: "🌲",  # WOOD
	1: "🧱",  # BRICK
	2: "⛏",  # ORE
	3: "🌾",  # WHEAT
	4: "🐑",  # SHEEP
	5: "🏜",  # DESERT
}

var hex_data = null

func setup(data) -> void:
	hex_data = data

	var pts: PackedVector2Array = []
	for i in 6:
		var angle := deg_to_rad(0.0 + 60.0 * i)
		pts.append(Vector2(cos(angle), sin(angle)) * 78.0)

	if not is_inside_tree():
		await tree_entered

	var polygon := $Polygon2D
	var label_emoji := $LabelEmoji
	var label_number := $LabelNumber
	var robber := $Robber
	var robber_circle := $Robber/RobberCircle
	var area := $Area2D
	var collision := $Area2D/CollisionPolygon2D

	polygon.polygon = pts
	collision.polygon = pts   # keep clickable area in sync with visual shape
	polygon.color = TERRAIN_COLORS[data.terrain]

	# Build a capsule polygon for the robber (tall, narrow, rounded ends)
	# Offset to the left so it doesn't cover the number/emoji
	const CAP_RADIUS : float = 9.0
	const BODY_HALF  : float = 14.0
	const CAP_SIDES  : int   = 8
	const OFFSET_X   : float = -28.0
	var capsule_pts: PackedVector2Array = []
	# Top cap: semicircle from 180° to 0° (left side → right side, above body)
	for i in CAP_SIDES + 1:
		var a := deg_to_rad(180.0 - 180.0 / CAP_SIDES * i)
		capsule_pts.append(Vector2(OFFSET_X + cos(a) * CAP_RADIUS, -BODY_HALF + sin(a) * CAP_RADIUS))
	# Bottom cap: semicircle from 0° to -180° (right side → left side, below body)
	for i in CAP_SIDES + 1:
		var a := deg_to_rad(-180.0 / CAP_SIDES * i)
		capsule_pts.append(Vector2(OFFSET_X + cos(a) * CAP_RADIUS, BODY_HALF + sin(a) * CAP_RADIUS))
	robber_circle.polygon = capsule_pts
	robber_circle.color   = Color.BLACK
	robber.position = Vector2.ZERO

	label_emoji.text = TERRAIN_LABELS[data.terrain]

	if data.number > 0:
		label_number.text = str(data.number)
		if data.number in [6, 8]:
			label_number.add_theme_color_override("font_color", Color.RED)
	else:
		label_number.text = ""

	robber.visible = data.has_robber

	area.input_event.connect(_on_input_event)
	GameManager.robber_moved.connect(_on_robber_moved)

# FIX: check MOVE_ROBBER phase, not BUILD
func _on_input_event(_viewport, event: InputEvent, _shape) -> void:
	if event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_phase == GameManager.Phase.MOVE_ROBBER:
			GameManager.move_robber(hex_data)

func _on_robber_moved() -> void:
	if not is_inside_tree():
		return
	var robber := $Robber
	robber.visible = hex_data.has_robber
