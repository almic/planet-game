class_name CharacterController extends RigidBody3D


@export_group('Movement')

## Acceleration rate in the desired direction.
@export_range(0.0, 3.0, 0.01, 'or_greater')
var acceleration: float = 16.0

## Stopping rate when controller should not move. Set to zero to disable stopping.
@export_range(0.0, 20.0, 0.01, 'or_greater')
var deceleration: float = 16.0

## How much speed to maintain when turning, reduces by this fraction every 15 degrees.
@export_range(0.001, 1.0, 0.001)
var turning_retention: float = 0.67

## How much speed to lose when traveling up slopes, reduces acceleration and
## speed by this fraction every 15 degrees of incline.
@export_range(0.0, 1.0, 0.001)
var incline_speed_reduction: float = 0.2

## How much speed to gain when traveling down slopes, increases acceleration
## and speed by this fraction every 15 degrees of decline. Set to 1.0 to disable
## speed up.
@export_range(1.0, 2.0, 0.001, 'or_greater')
var decline_speed_bonus: float = 1.1

## How much control to give in the air for ground-based controllers
@export_range(0.0, 1.0, 0.001)
var air_control: float = 0.5


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
var _velocity_debug_text: int = 0

@export var debug_forward: bool = false
var _forward_debug_vec: int = 0

@export var debug_normal: bool = false
var _normal_debug_vec: int = 0

@export var debug_friction: bool = false
var _friction_debug_vec: int = 0
var _friction_movement_debug_vec: int = 0

@export var debug_spring: bool = false
var _spring_debug_vec: int = 0


var is_on_floor: bool = false

## Force the controller to project desired velocity onto the ground, or if in
## the air, remove any vertical component and reproject to lateral movement
var force_ground_movement: bool = true

var desired_direction: Vector3 = Vector3.ZERO
var desired_speed: float = 0.0
var desired_incline_effect: float = 1.0

## The body's total speed
var linear_speed: float

## Velocity in the body's up direction
var vertical_velocity: Vector3

## Speed in the body's up direction
var vertical_speed: float

## Speed in the body's lateral direction, equivalent to linear_speed - vertical_speed
var lateral_speed: float

## Normal of the ground, is ZERO when no ground is detected
var ground_normal: Vector3

## Velocity of this body along the plane of the ground
var ground_velocity: Vector3

## Direction of this body along the plane of the ground
var ground_direction: Vector3 = ground_velocity.normalized()

## Calculated ground friction vector
var ground_friction: Vector3

## Calculated spring force
var spring_force: Vector3


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

    linear_speed = state.linear_velocity.length()
    vertical_velocity = state.transform.basis.y * state.transform.basis.tdoty(state.linear_velocity)
    vertical_speed = vertical_velocity.length()
    lateral_speed = linear_speed - vertical_speed

    # "Air drag"
    # (1/2) * Density * v^2 * Area * Coefficient
    var air_friction: Vector3 = Vector3.ZERO
    if not is_zero_approx(lateral_speed + vertical_speed):
        var lateral_ratio: float = clampf(lateral_speed / (lateral_speed + vertical_speed), 0.0, 1.0)
        air_friction = (
                0.5 * -1.21
                * state.linear_velocity.normalized() * linear_speed * linear_speed
                # Surface area, rough estimates
                * lerpf(0.09, 0.3, lateral_ratio)
                # Drag coefficient, falling calculated to result in 112m/s terminal speed
                # and lateral to roughly a sprinter's coefficient
                * lerpf(0.0143, 0.65, lateral_ratio)
        ) * state.inverse_mass # NOTE: Proportional to mass!!!

    # Ground detection and force
    if shape_cast.is_colliding():
        if not is_on_floor:
            is_on_floor = true

        if debug_enabled and debug_normal:
            _normal_debug_vec = DebugDraw.vector(
                    shape_cast.get_collision_point(0),
                    ground_normal * 0.5,
                    Color.CORNFLOWER_BLUE,
                    _normal_debug_vec,
                    2.0
            )

        _calculate_ground_force(state)

        if debug_enabled and debug_spring:
            _spring_debug_vec = DebugDraw.vector(
                shape_cast.global_position,
                state.total_gravity + (spring_force * state.inverse_mass),
                Color.DARK_SLATE_BLUE,
                _spring_debug_vec
            )

    elif is_on_floor:
        is_on_floor = false
        ground_normal = Vector3.ZERO
        ground_friction = Vector3.ZERO
        ground_direction = Vector3.ZERO
        ground_velocity = Vector3.ZERO
        spring_force = Vector3.ZERO

    var forward: Vector3 = Vector3.ZERO
    var speed_in_dir: float = linear_speed
    var limit_in_dir: float = desired_speed
    var accel_multiplier: float = 1.0

    if is_on_floor:

        if desired_speed > 0.0 and not desired_direction.is_zero_approx():
            # Moving on ground
            if force_ground_movement:
                forward = global_basis.y.cross(desired_direction).cross(ground_normal).normalized()
            else:
                forward = desired_direction

            # Limit forward acceleration
            speed_in_dir = ground_velocity.dot(forward)
            if desired_incline_effect > 0.0:
                var slope_cos_theta: float = state.transform.basis.tdoty(ground_direction)
                if slope_cos_theta > 0.0:
                    if incline_speed_reduction > 0.0:
                        var angle: float = asin(slope_cos_theta)
                        var loss: float = pow(clampf(1.0 - (incline_speed_reduction * desired_incline_effect), 0.001, 0.943), angle * (12.0 / PI))
                        limit_in_dir *= loss
                        accel_multiplier = loss
                elif slope_cos_theta < 0.0:
                    if decline_speed_bonus > 1.0:
                        var angle: float = asin(-slope_cos_theta)
                        var bonus: float = 1.0 + clampf((decline_speed_bonus - 1.0) * desired_incline_effect, 0.0, 1.0) * angle * (12.0 / PI)
                        limit_in_dir *= bonus
                        accel_multiplier = bonus

            # Reduce ground friction up to forward movement amount
            if not ground_friction.is_zero_approx():
                var ground_friction_speed: float = ground_friction.length()
                var ground_friction_dir: Vector3 = ground_friction / ground_friction_speed
                ground_friction -= ground_friction_dir * minf(limit_in_dir, ground_friction_speed)

            # Reduce air friction up to forward movement amount
            if not air_friction.is_zero_approx():
                var air_friction_speed: float = air_friction.length()
                var air_friction_dir: Vector3 = air_friction / air_friction_speed
                air_friction -= air_friction_dir * minf(limit_in_dir, air_friction_speed)

            # Add extra ground friction for turning/ changing direction/ over speed
            if not ground_velocity.is_zero_approx():
                var move_friction: Vector3
                if speed_in_dir > limit_in_dir:
                    move_friction = -ground_direction * minf(deceleration, (speed_in_dir - limit_in_dir) / state.step)
                else:
                    move_friction = _calculate_move_friction(forward)
                if debug_enabled and debug_friction:
                    _friction_movement_debug_vec = DebugDraw.vector(
                            global_position + (Vector3.UP * 0.45),
                            move_friction,
                            Color.DARK_GREEN,
                            _friction_movement_debug_vec,
                            2.0
                    )
                ground_friction += move_friction

        elif deceleration > 0.0 and not ground_velocity.is_zero_approx():
            # Stop quickly
            var max_stop_speed: float = ground_velocity.length()
            var ground_dir: Vector3 = ground_velocity / max_stop_speed

            # TODO: Account for gravity on slopes
            #max_stop_speed += ground_normal.dot(state.total_gravity)

            # Delta
            max_stop_speed /= state.step

            ground_friction += -ground_dir * minf(deceleration, max_stop_speed)
    elif force_ground_movement:
        # Air control
        if air_control > 0.0 and desired_speed > 0.0 and not desired_direction.is_zero_approx():
            forward = state.transform.basis.y.cross(desired_direction).cross(state.transform.basis.y).normalized()
            limit_in_dir *= air_control
            accel_multiplier = air_control
    else:
        forward = desired_direction

    # Add final friction values
    var friction: Vector3 = ground_friction + air_friction

    state.linear_velocity += state.step * (state.total_gravity + (spring_force * state.inverse_mass) + friction)

    if state.linear_velocity.length_squared() < 1.6e-5:
        state.linear_velocity = Vector3.ZERO

    if is_on_floor:
        # NOTE: Should be updated using new velocity, it is a little wrong like this
        speed_in_dir = ground_velocity.dot(forward)
    else:
        speed_in_dir = state.linear_velocity.dot(forward)

    if speed_in_dir < limit_in_dir:
        forward *= minf(acceleration * accel_multiplier, maxf(limit_in_dir - speed_in_dir, 0.0) / state.step)
        state.linear_velocity += forward * state.step

    if debug_enabled:
        if debug_velocity:
            _velocity_debug_vec = DebugDraw.vector(
                    global_position + (Vector3.UP * 0.55),
                    state.linear_velocity,
                    Color.FOREST_GREEN,
                    _velocity_debug_vec,
            )
            _velocity_debug_text = DebugDraw.text(
                    global_position + (Vector3.UP * 0.55),
                    '%.3f m/s' % linear_speed,
                    Color.FOREST_GREEN,
                    _velocity_debug_text
            )

        if debug_forward:
            var norm: Vector3 = forward
            if not norm.is_zero_approx():
                norm = norm.normalized()
            _forward_debug_vec = DebugDraw.vector(
                    global_position + (Vector3.UP * 0.5),
                    norm,
                    Color.GREEN_YELLOW,
                    _forward_debug_vec,
                    2.0
            )

        if debug_friction:
            _friction_debug_vec = DebugDraw.vector(
                global_position + (Vector3.UP * 0.45),
                friction,
                Color.FIREBRICK,
                _friction_debug_vec,
                2.0
            )

## Calculate a ground force using a spring-mass-damper simulation and friction
func _calculate_ground_force(state: PhysicsDirectBodyState3D) -> void:

    ground_normal = shape_cast.get_collision_normal(0)

    var max_length: float = shape_cast.target_position.length()
    var spring_direction: Vector3 = -(shape_cast.target_position / max_length)
    var length: float = shape_cast.get_closest_collision_safe_fraction() * max_length

    var offset: float = (max_length + height_offset) - length
    var spring: float = mass * 100.0 * spring_stiffness * offset

    var ground: Object = shape_cast.get_collider(0)
    var ground_state: PhysicsDirectBodyState3D = null
    var ground_contact_velocity: Vector3 = Vector3.ZERO

    var friction_coef: float

    if ground is PhysicsBody3D:
        ground_state = PhysicsServer3D.body_get_direct_state(ground.get_rid())

        friction_coef = absf(minf(
                PhysicsServer3D.body_get_param(get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION),
                PhysicsServer3D.body_get_param(ground.get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION)
        ))
    else:
        friction_coef = absf(PhysicsServer3D.body_get_param(get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION))

    var local_position: Vector3 = Vector3.ZERO
    if ground_state:
        local_position = shape_cast.get_collision_point(0) - ground_state.transform.origin
        ground_contact_velocity = ground_state.get_velocity_at_local_position(local_position)

    if ground_contact_velocity.is_zero_approx():
        ground_velocity = state.linear_velocity.slide(ground_normal)
        ground_friction = friction_coef * -ground_velocity
    else:
        var relative_contact_velocity: Vector3 = ground_contact_velocity - state.linear_velocity

        # Use relative velocity as ground velocity
        ground_velocity = -relative_contact_velocity.slide(ground_normal)

        # Ground friction in m/s^2
        ground_friction = friction_coef * relative_contact_velocity.slide(ground_normal)

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO

    # NOTE: Math trick, these two lines are equivalent
    #       1) A.dot(N) * B.dot(N)  OR  N.dot(A) * N.dot(B)
    #       2) A.dot(N * N.dot(B))
    var spring_velocity: float = (
              ground_normal.dot(spring_direction)
            * ground_normal.dot(state.linear_velocity - ground_contact_velocity)
    )
    var damp: float = minf(mass * 10.0 * spring_damping * spring_velocity, spring)

    spring_force = (
        clampf(spring - damp, 0.0, 1e8) * spring_direction
        # TODO: check if this is needed
        * clampf(ground_normal.dot(spring_direction), 0.0, 1.0)
    )

    if ground_state:
        # Apply opposing spring force to body, invert ground velocity to push back
        ground_state.apply_force(-1.0 * (spring_force + ground_velocity * mass), local_position)

## Calculate additional ground friction for turning/ changing direction
func _calculate_move_friction(forward: Vector3) -> Vector3:
    var cos_theta: float = clampf(ground_direction.dot(forward), -1.0, 1.0)

    # No friction if wish direction and movement match
    if cos_theta == 1.0:
        return Vector3.ZERO

    var angle: float = acos(cos_theta)

    # More friction in similar directions, reduce slidey feel when
    # strafing perpendicular to direction of motion
    if cos_theta > 0.5:
        cos_theta = angle * (2 / PI)

    var loss: float = (1.0 - cos_theta) * deceleration

    # Retain some speed when turning, multiplier is per 15* of difference
    var keep: float = pow(clampf(turning_retention, 0.001, 0.943), angle * (12.0 / PI))

    # Allow counter-strafing at "half" the normal rate, reduces jumpy feeling
    if cos_theta <= 0.0:
        keep *= keep

    return -ground_direction * loss + forward * loss * keep
