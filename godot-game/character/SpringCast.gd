## Helper for spring-like shape cast nodes
class_name SpringCast extends ShapeCast3D




## Offset from the shape cast's maximum extent
@export_range(-10.0, 10.0, 0.01, 'or_less', 'or_greater')
var height_offset: float = 0.0

@export_range(0.01, 2.0, 0.01, 'or_greater')
var stiffness: float = 2.5

@export_range(0.01, 1.0, 0.01, 'or_greater')
var damping: float = 2.2

## If the calculated forces should be applied in the contact normal direction.
## When set to false, only applies in the spring's direction.
@export var apply_on_normal: bool = true


var total_force: Vector3 = Vector3.ZERO
var total_lambda: float = 0.0

var direction: Vector3
var max_length: float

var length: float = INF
var last_length: float = INF

## Global contact position
var contact_point: Vector3 = Vector3.INF

## Collision contact normal
var normal: Vector3 = Vector3.ZERO

## Main body's RID
var body_rid: RID

## Collision body's mode
var other_mode: PhysicsServer3D.BodyMode = PhysicsServer3D.BodyMode.BODY_MODE_STATIC

## Collision body's RID
var other_rid: RID


var _body_axis: Vector3
var _other_axis: Vector3


func _ready() -> void:
    update_target()


## Call this when changing the direction or length of a spring
func update_target() -> void:
    max_length = target_position.length()
    direction = -(target_position / max_length)
    last_length = INF

## Call to update the shape cast
func cast() -> void:
    force_shapecast_update()

## Reads the current spring collision state and caches it
func save_state() -> void:
    if not is_colliding():
        length = INF
        normal = Vector3.ZERO
        contact_point = Vector3.INF
        other_rid = RID()
        other_mode = PhysicsServer3D.BodyMode.BODY_MODE_STATIC
        return

    normal = get_collision_normal(0)
    length = get_closest_collision_safe_fraction() * max_length
    contact_point = get_collision_point(0)
    other_rid = get_collider_rid(0)
    other_mode = PhysicsServer3D.body_get_mode(other_rid)

## Solves spring forces and applies accelerations to the main and colliding body
func solve_forces(delta: float, extra_offset: float = 0.0, _restitution: float = 0.0) -> void:

    # TODO: iteratively update velocities and positions for better spring results.
    const ITERATIONS: int = 2

    var body_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(body_rid)
    var other_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(other_rid)

    # Reset lambda at the start
    total_lambda = 0.0

    if is_inf(length) or ((not body_state) and (not other_state)):
        total_force = Vector3.ZERO
        return

    var body_linear: bool = false
    var body_angular: bool = false
    var body_static: bool = false

    if body_state:
        var mode: PhysicsServer3D.BodyMode = PhysicsServer3D.body_get_mode(body_rid)
        if mode == PhysicsServer3D.BodyMode.BODY_MODE_KINEMATIC:
            body_linear = true
        elif mode == PhysicsServer3D.BodyMode.BODY_MODE_RIGID:
            body_linear = true
            body_angular = true
        elif mode == PhysicsServer3D.BodyMode.BODY_MODE_RIGID_LINEAR:
            body_linear = true
        elif mode == PhysicsServer3D.BodyMode.BODY_MODE_STATIC:
            body_static = true

    var other_linear: bool = false
    var other_angular: bool = false
    var other_static: bool = false

    if other_state:
        if other_mode == PhysicsServer3D.BodyMode.BODY_MODE_KINEMATIC:
            other_linear = true
        elif other_mode == PhysicsServer3D.BodyMode.BODY_MODE_RIGID:
            other_linear = true
            other_angular = true
        elif other_mode == PhysicsServer3D.BodyMode.BODY_MODE_RIGID_LINEAR:
            other_linear = true
        elif other_mode == PhysicsServer3D.BodyMode.BODY_MODE_STATIC:
            other_static = true

    if body_static and other_static:
        total_force = Vector3.ZERO
        return

    var force_normal: Vector3
    if apply_on_normal:
        force_normal = -normal
    else:
        force_normal = -direction

    var inv_effective_mass: float
    if (not body_static) and (not other_static):
        inv_effective_mass = _calculate_inverse_effective_mass(body_state, other_state)
    elif other_static:
        inv_effective_mass = _calculate_inverse_effective_mass(body_state, null)
    else:
        inv_effective_mass = _calculate_inverse_effective_mass(null, other_state)

    # Inverse mass can be very small, so only equate to zero
    if inv_effective_mass == 0.0:
        return

    var softness: float = 1.0 / (delta * (damping + delta * stiffness))
    var effective_mass = 1.0 / (inv_effective_mass + softness)

    for i in range(ITERATIONS):

        var body_velocity: Vector3
        if body_state:
            body_velocity = body_state.get_velocity_at_local_position(contact_point - body_state.transform.origin)

        var other_velocity: Vector3
        if other_state:
            other_velocity = other_state.get_velocity_at_local_position(contact_point - other_state.transform.origin)

        var relative_contact_velocity: Vector3 = body_velocity - other_velocity

        # TODO: update positions and try to recast the shape to see if the position
        #       changes actually affect the spring cast.
        var offset: float = length - (max_length + height_offset + extra_offset)
        var bias: float = delta * stiffness * softness * offset
        var jv: float = (-normal).dot(relative_contact_velocity)

        var lambda: float = effective_mass * (jv - (softness * total_lambda + bias))
        lambda = clampf(total_lambda + lambda, 0.0, 2000.0)
        var delta_lambda: float = lambda - total_lambda
        total_lambda = lambda

        if not body_static:
            if body_linear:
                body_state.linear_velocity -= delta_lambda * body_state.inverse_mass * force_normal
            if body_angular:
                body_state.angular_velocity -= delta_lambda * _body_axis

        if not other_static:
            if other_linear:
                other_state.linear_velocity += delta_lambda * other_state.inverse_mass * force_normal
            if other_angular:
                other_state.angular_velocity += delta_lambda * _other_axis

    total_force = direction * total_lambda

## Calculates an effective inverse mass, which is the sum of both inverse masses and their inertia
## at the collision point. This also updates a rotation axis used to apply angular acceleration.
func _calculate_inverse_effective_mass(body_state: PhysicsDirectBodyState3D, other_state: PhysicsDirectBodyState3D) -> float:
    var inv_effective_mass: float = 0.0

    if body_state:
        var relative: Vector3 = contact_point - (body_state.transform.origin + body_state.center_of_mass)
        var axis: Vector3 = relative.cross(normal)
        _body_axis = body_state.inverse_inertia_tensor * axis
        inv_effective_mass += body_state.inverse_mass + axis.dot(_body_axis)

    if other_state:
        var relative: Vector3 = contact_point - (other_state.transform.origin + other_state.center_of_mass)
        var axis: Vector3 = relative.cross(normal)
        _other_axis = other_state.inverse_inertia_tensor * axis
        inv_effective_mass += other_state.inverse_mass + axis.dot(_other_axis)

    return inv_effective_mass
