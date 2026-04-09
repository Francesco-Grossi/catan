extends Resource
class_name PlayerData

var player_index: int = 0
var color: Color = Color.WHITE

var resources: Dictionary = {
	GameManager.Resource.WOOD:  0,
	GameManager.Resource.BRICK: 0,
	GameManager.Resource.ORE:   0,
	GameManager.Resource.WHEAT: 0,
	GameManager.Resource.SHEEP: 0,
}

var dev_cards: Array[String] = []
var victory_points: int = 0
var settlements: int = 0
var cities: int = 0
var roads: int = 0
var longest_road_length: int = 0
var has_longest_road: bool = false
var has_largest_army: bool = false
var knights_played: int = 0

func total_resources() -> int:
	var total := 0
	for r in resources.values():
		total += r
	return total
