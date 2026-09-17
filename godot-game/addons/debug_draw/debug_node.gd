class_name DebugNode3D extends Node3D


## Radius of the sphere drawn
@export_range(0.01, 1.0, 0.01, 'or_greater')
var radius: float = 0.1

## Color of the sphere drawn
@export var color: Color = Color.DEEP_PINK

## When removed or disabled, how long should the sphere linger
@export_range(0.0, 1.0, 0.01, 'or_greater')
var linger_time: float = 0.0


var debug_id: int
var enabled: bool = true:
    set(value):
        if value:
            process_mode = Node.PROCESS_MODE_INHERIT
        else:
            process_mode = Node.PROCESS_MODE_DISABLED
    get():
        return process_mode != Node.PROCESS_MODE_DISABLED


func _process(_delta) -> void:
    debug_id = DebugDraw.sphere(
            global_position,
            radius,
            color,
            debug_id,
            linger_time
    )
