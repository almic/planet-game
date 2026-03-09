extends RigidBody3D

@export var extension_length: float = 7.0
@export var extension_acceleration: float = 200.0

var rest_plane: Plane
var timer: float = 1.0
var extending: bool = false
var waiting: bool = true

func _ready() -> void:
    rest_plane = Plane(global_basis.z, global_position)

func _physics_process(delta: float) -> void:
    if not extending:
        if timer > 0.0:
            timer -= delta
            return

        if waiting:
            waiting = false
            extending = true
        elif rest_plane.distance_to(global_position) > 0.001:
            linear_velocity = global_basis.z * -1.0
            return
        else:
            waiting = true
            global_position = rest_plane.project(global_position)
            linear_velocity = Vector3.ZERO
            timer = 2.0
            return

    if not extending:
        return

    if timer > 0.0:
        timer -= delta
        if timer <= 0.0:
            extending = false
            timer = 1.0
        return

    if rest_plane.distance_to(global_position) < extension_length:
        linear_velocity += global_basis.z * extension_acceleration * delta
    else:
        global_position = rest_plane.project(global_position) + global_basis.z * extension_length
        linear_velocity = Vector3.ZERO
        timer = 1.0
