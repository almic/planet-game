class_name CharacterController extends RigidBody3D


@export_group('Movement')

## Acceleration rate in the desired direction. Set this to zero to always move
## at max_speed.
@export_range(0.0, 3.0, 0.01, 'or_greater')
var acceleration: float = 1.0

## Maximum speed, will stop accelerating from input when this speed is reached.
## Set to zero to have no limit, requires acceleration to be positive, otherwise
## 1.0 is used as the max speed.
@export_range(0.0, 10.0, 0.01, 'or_greater')
var max_speed: float = 5.0

## Stopping rate when controller should not move. Set to zero to disable stopping.
@export_range(0.0, 20.0, 0.01, 'or_greater')
var deceleration: float = 14.0


@export_group('Floor Collision')

## Shape cast to use for colliding with the ground, like a spring. Set up the
## shape cast such that its extent is equal to the step-down height.
@export var shape_cast: ShapeCast3D

## Offset from the shape cast's maximum extent, use this to subtract the step-down
## height added.
@export_range(-10.0, 10.0, 0.01, 'or_less', 'or_greater')
var height_offset: float = 0.0

@export var spring_stiffness: float = 1.5

@export var spring_damping: float = 1.8


@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enabled: bool = false

@export var debug_velocity: bool = false
var _velocity_debug_vec: int = 0

@export var debug_forward: bool = false
var _forward_debug_vec: int = 0

@export var debug_normal: bool = false
var _normal_debug_vec: int = 0

@export var debug_friction: bool = false
var _friction_debug_vec: int = 0

@export var debug_spring: bool = false
var _spring_debug_vec: int = 0


var is_on_floor: bool = false

## Force the controller to project desired velocity onto the ground, or if in
## the air, remove any vertical component and reproject to lateral movement
var force_ground_movement: bool = true
var desired_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
    # At least 1 result is needed for ground slope detection
    if shape_cast.max_results == 0:
        shape_cast.max_results = 1

## Implement per controller, called when input should be read for movement.
## If your controller has a camera connect to mouse movement, you should handle
## that directly in _process() instead.
func _handle_input() -> void:
    pass


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:

    _handle_input()

    if not shape_cast.is_colliding():
        if is_on_floor:
            is_on_floor = false
        state.linear_velocity += state.total_gravity * state.step
        return

    if not is_on_floor:
        is_on_floor = true

    var max_length: float = shape_cast.target_position.length()
    var spring_direction: Vector3 = -(shape_cast.target_position / max_length)
    var length: float = shape_cast.get_closest_collision_safe_fraction() * max_length
    var normal: Vector3 = shape_cast.get_collision_normal(0)

    var offset: float = (max_length + height_offset) - length
    var spring: float = mass * 100.0 * spring_stiffness * offset

    var push: Vector3

    var ground: Object = shape_cast.get_collider(0)
    var vertical_velocity: Vector3 = global_basis.y * global_basis.tdoty(state.linear_velocity)
    var ground_velocity: Vector3 = state.linear_velocity - vertical_velocity
    if ground is RigidBody3D:
        var body_state := PhysicsServer3D.body_get_direct_state(ground.get_rid())
        var local_position: Vector3 = shape_cast.get_collision_point(0) - ground.global_position

        var body_contact_velocity = body_state.get_velocity_at_local_position(local_position)

        var ground_vertical_velocity: Vector3 = global_basis.y * global_basis.tdoty(body_contact_velocity)

        var spring_velocity: float = spring_direction.dot(state.linear_velocity - body_contact_velocity)
        var damp: float = minf(mass * 10.0 * spring_damping * spring_velocity, spring)

        push = (
            clampf(spring - damp, 0.0, 1e8) * spring_direction * clampf(normal.dot(spring_direction), 0.5, 1.0)
        )
        ground_velocity -= body_contact_velocity - ground_vertical_velocity
        body_state.apply_force(-1.0 * (push + (ground_velocity * mass)), local_position)
    else:
        var spring_velocity: float = spring_direction.dot(normal) * state.linear_velocity.dot(normal)
        var damp: float = minf(mass * 10.0 * spring_damping * spring_velocity, spring)
        push = (
            clampf(spring - damp, 0.0, 1e8) * spring_direction * clampf(normal.dot(spring_direction), 0.5, 1.0)
        )

    var forward: Vector3 = desired_velocity
    var wants_move: bool = not desired_velocity.is_zero_approx()
    if force_ground_movement and wants_move:
        var desired_speed: float = desired_velocity.length()
        var desired_direction: Vector3 = desired_velocity / desired_speed
        forward = global_basis.y.cross(desired_direction).cross(normal).normalized()
        forward *= desired_speed

    var linear_speed: float = state.linear_velocity.length()
    var vertical_speed: float = vertical_velocity.length()

    var friction: Vector3 = Vector3.ZERO

    # "Air drag"
    # (1/2) * Density * v^2 * Area * Coefficient
    if not is_zero_approx(linear_speed + vertical_speed):
        var lateral_ratio: float = clampf(linear_speed / (linear_speed + vertical_speed), 0.0, 1.0)
        friction += (
                0.5 * 1.21
                * state.linear_velocity * state.linear_velocity.abs()
                * lerpf(0.09, 0.3, lateral_ratio)
                * lerpf(0.01, 0.65, lateral_ratio)
        )

    if not wants_move and not ground_velocity.is_zero_approx():
        # Stop quickly
        var ground_speed: float = ground_velocity.length()
        var ground_dir: Vector3 = ground_velocity / ground_speed
        friction += ground_dir * minf(deceleration, ground_speed / state.step)

    state.linear_velocity += state.step * (state.total_gravity + (push * state.inverse_mass) + forward - friction)
    if state.linear_velocity.length_squared() < 1.6e-5:
        state.linear_velocity = Vector3.ZERO

    if debug_enabled:
        if debug_velocity:
            _velocity_debug_vec = DebugDraw.vector(
                    global_position + (Vector3.UP * 0.55),
                    state.linear_velocity,
                    Color.FOREST_GREEN,
                    _velocity_debug_vec,
            )

        if debug_forward:
            _forward_debug_vec = DebugDraw.vector(
                    global_position + (Vector3.UP * 0.5),
                    forward.normalized(),
                    Color.GREEN_YELLOW,
                    _forward_debug_vec,
                    2.0
            )

        if debug_normal:
            _normal_debug_vec = DebugDraw.vector(
                    shape_cast.get_collision_point(0),
                    normal * 0.5,
                    Color.CORNFLOWER_BLUE,
                    _normal_debug_vec,
                    2.0
            )

        if debug_friction:
            _friction_debug_vec = DebugDraw.vector(
                global_position + (Vector3.UP * 0.45),
                -friction,
                Color.FIREBRICK,
                _friction_debug_vec,
                2.0
            )

        if debug_spring:
            _spring_debug_vec = DebugDraw.vector(
                shape_cast.global_position,
                state.total_gravity + (push * state.inverse_mass),
                Color.DARK_SLATE_BLUE,
                _spring_debug_vec
            )
