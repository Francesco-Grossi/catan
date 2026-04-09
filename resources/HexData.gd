extends Resource
class_name HexData

var q: int = 0
var r: int = 0
var terrain: GameManager.Terrain = GameManager.Terrain.DESERT
var number: int = 0
var has_robber: bool = false
var vertex_nodes: Array = []   # VertexPoint references (set by Board)
var edge_nodes: Array = []     # EdgePoint references (set by Board)
