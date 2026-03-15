@tool
class_name CrawlerLeg extends Node3D

@export var shape_cast: ShapeCast3D
@export var target: Marker3D

var is_grounded: bool = false

func _ready() -> void:
    if not shape_cast:
        for child in find_children('', 'ShapeCast3D', false):
            shape_cast = child as ShapeCast3D
            if shape_cast:
                break
    if not target:
        for child in find_children('', 'Marker3D', false):
            target = child as Marker3D
            if target:
                break

    # Ensure target is top-level
    target.top_level = true

func update() -> void:
    # Move targets to collision point
    if shape_cast.is_colliding():
        target.transform.origin = shape_cast.get_collision_point(0)
        is_grounded = true
    else:
        is_grounded = false
