extends Node2D

const TERRAIN_COLORS: Dictionary = {
	GameManager.Terrain.WOOD:    Color(0.13, 0.55, 0.13),
	GameManager.Terrain.BRICK:   Color(0.78, 0.31, 0.08),
	GameManager.Terrain.ORE:     Color(0.55, 0.55, 0.55),
	GameManager.Terrain.WHEAT:   Color(0.93, 0.83, 0.10),
	GameManager.Terrain.SHEEP:   Color(0.56, 0.93, 0.56),
	GameManager.Terrain.DESERT:  Color(0.87, 0.80, 0.55),
}

const TERRAIN_LABELS: Dictionary = {
	GameManager.Terrain.WOOD:   "🌲",
	GameManager.Terrain.BRICK:  "🧱",
	GameManager.Terrain.ORE:    "⛏",
	GameManager.Terrain.WHEAT:  "🌾",
	GameManager.Terrain.SHEEP:  "🐑",
	GameManager.Terrain.DESERT: "🏜",
}

@onready var polygon: Polygon2D      = $Polygon2D
@onready var label_emoji: Label      = $LabelEmoji
@onready var label_number: Label     = $LabelNumber
@onready var robber_sprite: Node2D   = $Robber

var hex_data: HexData

func setup(data: HexData) -> void:
	hex_data = data
	var pts: PackedVector2Array = []
	for i in 6:
		var angle := deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(angle), sin(angle)) * 78.0)
	polygon.polygon = pts
	polygon.color = TERRAIN_COLORS[data.terrain]
	label_emoji.text = TERRAIN_LABELS[data.terrain]
	if data.number > 0:
		label_number.text = str(data.number)
		if data.number in [6, 8]:
			label_number.add_theme_color_override("font_color", Color.RED)
	else:
		label_number.text = ""
	robber_sprite.visible = data.has_robber

	# Allow clicking hex to move robber
	$Area2D.input_event.connect(_on_input_event)
	GameManager.robber_moved.connect(_on_robber_moved)

func _on_input_event(_viewport, event: InputEvent, _shape) -> void:
	if event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_phase == GameManager.Phase.BUILD:
			# Only allow during robber placement (after 7)
			GameManager.move_robber(hex_data)

func _on_robber_moved() -> void:
	robber_sprite.visible = hex_data.has_robber
