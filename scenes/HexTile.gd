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

	# Build hex polygon points
	var pts: PackedVector2Array = []
	for i in 6:
		var angle := deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(angle), sin(angle)) * 78.0)

	# Wait until inside tree so @onready nodes are valid
	if not is_inside_tree():
		await tree_entered

	var polygon := $Polygon2D
	var label_emoji := $LabelEmoji
	var label_number := $LabelNumber
	var robber := $Robber
	var area := $Area2D

	polygon.polygon = pts
	polygon.color = TERRAIN_COLORS[data.terrain]

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

func _on_input_event(_viewport, event: InputEvent, _shape) -> void:
	if event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_phase == GameManager.Phase.BUILD:
			GameManager.move_robber(hex_data)

func _on_robber_moved() -> void:
	if not is_inside_tree():
		return
	var robber := $Robber
	robber.visible = hex_data.has_robber
