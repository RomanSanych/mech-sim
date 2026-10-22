extends Node2D
## Живой слой схемы (давление, поршень/золотник, шевроны, hover при Run). Owner = SchematicView.

var owner_view: Control = null


func _draw() -> void:
	if owner_view != null and owner_view.has_method("draw_live_layer"):
		owner_view.draw_live_layer(self)
