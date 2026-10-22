extends Node2D
## Статический слой схемы (провода, УГО, номера). Owner = SchematicView.

var owner_view: Control = null


func request_draw() -> void:
	queue_redraw()


func _draw() -> void:
	if owner_view != null and owner_view.has_method("draw_base_layer"):
		owner_view.draw_base_layer(self)
