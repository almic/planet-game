## Helper to estimate angle constraint responses between two bodies.
## This is effectively an implementation of Jolt AngleConstraintPart.
extends RefCounted


var _inv_i1: Vector3
var _inv_i2: Vector3
var _effective_mass: float
var _total_lambda: float
var _bias: float


func apply_velocity_step(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        lambda: float,
) -> bool:
    if lambda == 0.0:
        return false

    parent.angular_velocity -= _inv_i1 * lambda
    body.angular_velocity += _inv_i2 * lambda

    return true

func set_total_lambda(total_lambda: float) -> void:
    _total_lambda = total_lambda

func setup(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        world_axis: Vector3,
        bias: float = 0.0
) -> void:

    _inv_i1 = _mult_world_inertia_vector(parent, world_axis)
    _inv_i2 = _mult_world_inertia_vector(body, world_axis)

    var inv_effective_mass: float = world_axis.dot(_inv_i1 + _inv_i2)
    if inv_effective_mass == 0.0:
        deactivate()
        return

    _effective_mass = 1.0 / inv_effective_mass
    _bias = bias

func deactivate() -> void:
    _effective_mass = 0.0
    _total_lambda = 0.0

func is_active() -> bool:
    return _effective_mass != 0.0

func warm_start(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> void:
    apply_velocity_step(parent, body, _total_lambda)

func solve_velocity(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        axis: Vector3,
        min_lambda: float,
        max_lambda: float,
) -> bool:
    var lambda: float = _effective_mass * (axis.dot(parent.angular_velocity - body.angular_velocity) - _bias)
    var new_lambda: float = clampf(_total_lambda + lambda, min_lambda, max_lambda)
    lambda = new_lambda - _total_lambda
    _total_lambda = new_lambda

    var result: bool = apply_velocity_step(parent, body, lambda)
    var joint_velocity: float = axis.dot(parent.angular_velocity - body.angular_velocity)
    return result

func _mult_world_inertia_vector(body: PhysicsDirectBodyState3D, v: Vector3) -> Vector3:
    var rotation: Basis = body.principal_inertia_axes
    var result: Vector3 = rotation * (body.inverse_inertia_diagonal * (rotation.transposed() * v))

    return result
