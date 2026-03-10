extends RigidBody3D

@export var extension_length: float = 7.0
@export var extension_acceleration: float = 2.0
@export var return_acceleration: float = 2.0

var rest_plane: Plane
var timer: float = 1.0
var extending: bool = false
var waiting: bool = true

func _ready() -> void:
    rest_plane = Plane(global_basis.z, global_position)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    state.linear_velocity -= state.linear_velocity * state.total_linear_damp * state.step

    if not extending:
        if timer > 0.0:
            timer -= state.step
            return

        if waiting:
            waiting = false
            extending = true
        elif rest_plane.distance_to(global_position) > 0.001:
            state.linear_velocity -= global_basis.z * absf(return_acceleration) * state.step
            return
        else:
            waiting = true
            state.transform.origin = rest_plane.project(global_position)
            state.linear_velocity = Vector3.ZERO
            timer = 2.0
            return

    if not extending:
        return

    if timer > 0.0:
        timer -= state.step
        if timer <= 0.0:
            extending = false
            timer = 1.0
        return

    if rest_plane.distance_to(global_position) < extension_length:
        state.linear_velocity += global_basis.z * extension_acceleration * state.step
    else:
        state.transform.origin = rest_plane.project(global_position) + global_basis.z * extension_length
        state.linear_velocity = Vector3.ZERO
        timer = 1.0
