extends Node3D

var debug_id: int

func _ready() -> void:
    return
    var modifier: SkeletonModifier3D = get_parent() as SkeletonModifier3D
    modifier.modification_processed.connect(draw_debug)

func draw_debug() -> void:
    debug_id = DebugDraw.sphere(
            get_parent().global_position,
            0.01,
            Color.LIGHT_GREEN,
            debug_id
    )
