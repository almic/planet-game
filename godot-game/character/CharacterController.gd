@tool
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

## The floor angle at which point the controller will not be able to climb. This
## adds a "slip" force by reprojecting gravity in the downhill direction.
@export_range(0.0, 89.0, 0.1, 'radians_as_degrees')
var max_slope_angle: float = deg_to_rad(55)

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
@export var spring: SpringCast


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
var is_slipping: bool = false
## This prevents jumping continuously up steep ground. Must land on flat ground to become true,
## set to false upon performing a jump.
var has_landed_on_ground_for_jump: bool = false

## If the character body is currently applying forward movement
var has_desired_forward: bool:
    get():
        return desired_speed > 0.0 and not desired_direction.is_zero_approx()

## Force the controller to project desired velocity onto the ground, or if in
## the air, remove any vertical component and reproject to lateral movement
var force_ground_movement: bool = true

## When true, CharacterController will not call '_handle_input()' automatically
var manual_input_handling: bool = false

var desired_direction: Vector3 = Vector3.ZERO
var desired_speed: float = 0.0
var desired_incline_effect: float = 1.0
var desired_jump_power: float = 0.0
## Additional offset for the spring height
var desired_height_offset: float = 0.0
## Multiplier to gravity acceleration
var desired_gravity: float = 1.0

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
var ground_direction: Vector3

## Calculated ground friction vector
var ground_friction: Vector3

## Relative contact velocity with the ground
var ground_rel_con_velocity: Vector3

## Calculated wall slide normal, only use when is_slipping is true
var wall_slide_normal: Vector3


func _ready() -> void:

    # Make this body use custom integrator
    custom_integrator = true

    # Setup spring
    if spring:
        spring.mass = mass

        # At least 1 result is needed for ground slope detection
        if spring.max_results == 0:
            spring.max_results = 1

## Implement per controller, called when input should be read for movement.
## If your controller has a camera connect to mouse movement, you should handle
## that directly in _process() instead.
func _handle_input() -> void:
    pass


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:

    if not manual_input_handling:
        _handle_input()

    linear_speed = state.linear_velocity.length()
    vertical_velocity = state.transform.basis.y * state.transform.basis.tdoty(state.linear_velocity)
    vertical_speed = vertical_velocity.length()
    lateral_speed = linear_speed - vertical_speed

    var gravity: Vector3 = state.total_gravity * desired_gravity

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
    _calculate_ground_force(state)

    if is_on_floor and spring and debug_enabled:
        if debug_normal:
            _normal_debug_vec = DebugDraw.vector(
                    spring.get_collision_point(0),
                    ground_normal * 0.5,
                    Color.CORNFLOWER_BLUE,
                    _normal_debug_vec,
                    2.0
            )
        if debug_spring:
            _spring_debug_vec = DebugDraw.vector(
                spring.global_position,
                gravity + spring.total_force,
                Color.DARK_SLATE_BLUE,
                _spring_debug_vec
            )

    var forward: Vector3 = Vector3.ZERO
    var speed_in_dir: float = linear_speed
    var limit_in_dir: float = desired_speed
    var accel_multiplier: float = 1.0

    if is_on_floor:

        if has_desired_forward:
            # Stable ground movement, only when not already calculated from steep ground
            if force_ground_movement:
                forward = state.transform.basis.y.cross(desired_direction).cross(ground_normal).normalized()
                speed_in_dir = ground_velocity.dot(forward)
                if is_slipping:
                    var wall_normal: Vector3 = Vector3(wall_slide_normal.x, 0.0, wall_slide_normal.z).normalized()
                    var slip_forward: Vector3 = state.transform.basis.y.cross(desired_direction).cross(state.transform.basis.y).normalized()
                    forward = slip_forward
                    # If forward is against wall, do additional speed reductions and clamp forward to wall
                    if wall_normal.dot(forward) < 0.0:
                        var slip_mult: float = slip_forward.dot(slip_forward.slide(wall_normal))
                        limit_in_dir *= slip_mult
                        accel_multiplier *= slip_mult
                        forward = forward.slide(wall_normal)
                        if not forward.is_zero_approx():
                            forward = forward.normalized()
            else:
                forward = desired_direction
                speed_in_dir = ground_velocity.dot(forward)

            # Limit forward acceleration
            if desired_incline_effect > 0.0:
                var slope_cos_theta: float = state.transform.basis.tdoty(forward)
                if slope_cos_theta > 0.0:
                    if incline_speed_reduction > 0.0:
                        var angle: float = asin(slope_cos_theta)
                        var loss: float = pow(clampf(1.0 - (incline_speed_reduction * desired_incline_effect), 0.001, 0.943), angle * (12.0 / PI))
                        limit_in_dir *= loss
                        accel_multiplier *= loss
                elif slope_cos_theta < 0.0:
                    if decline_speed_bonus > 1.0:
                        var angle: float = asin(-slope_cos_theta)
                        var bonus: float = 1.0 + clampf((decline_speed_bonus - 1.0) * desired_incline_effect, 0.0, 1.0) * angle * (12.0 / PI)
                        limit_in_dir *= bonus
                        accel_multiplier *= bonus

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
            if (not is_slipping) and (not ground_velocity.is_zero_approx()):
                var move_friction: Vector3
                if speed_in_dir > limit_in_dir:
                    move_friction = -ground_direction * minf(deceleration, (speed_in_dir - limit_in_dir) / state.step)
                else:
                    move_friction = _calculate_move_friction(forward)
                if debug_enabled and debug_friction:
                    _friction_movement_debug_vec = DebugDraw.vector(
                            state.transform.origin + (Vector3.UP * 0.45),
                            move_friction,
                            Color.DARK_GREEN,
                            _friction_movement_debug_vec,
                            2.0
                    )
                ground_friction += move_friction

        elif (not is_slipping) and deceleration > 0.0 and not ground_velocity.is_zero_approx():
            # TODO: Stopping friction is causing weird interactions on slopes.
            #       This must be addressed by trying new ways to calculate it here.

            # Stop quickly
            var relative_ground: Vector3 = (
                    # Vertical stopping component with spring correction
                    state.transform.basis.y * state.transform.basis.tdoty(ground_velocity)
                  + ground_rel_con_velocity.slide(state.transform.basis.y)
            )

            var ground_speed: float = relative_ground.length()
            var ground_dir: Vector3 = relative_ground / ground_speed

            var max_stop_speed: float = ground_speed / state.step
            var stop_len: float = minf(deceleration, max_stop_speed)
            var stop_friction: Vector3 = -ground_dir * stop_len

            if not stop_friction.is_zero_approx():

                # remove spring + gravity
                if spring and (not spring.total_force.is_zero_approx()):
                    var spring_vel: Vector3 = gravity + (spring.total_force * state.inverse_mass)
                    var spring_len: float = spring_vel.length()
                    var spring_dir: Vector3 = spring_vel / spring_len

                    var cos_theta: float = ground_dir.dot(spring_dir)
                    stop_friction += ground_dir * minf(spring_len * absf(cos_theta), stop_len)

                ground_friction += stop_friction

    elif force_ground_movement:
        # Air control
        if air_control > 0.0 and has_desired_forward:
            forward = state.transform.basis.y.cross(desired_direction).cross(state.transform.basis.y).normalized()
            accel_multiplier *= air_control
    else:
        forward = desired_direction

    # Jumping, reset power to zero when activated
    var jump: Vector3 = Vector3.ZERO
    if desired_jump_power > 0.0:
        if is_on_floor and has_landed_on_ground_for_jump:
            if forward.is_zero_approx():
                jump = 0.6 * state.transform.basis.y + 0.4 * ground_normal
            else:
                jump = 0.8 * state.transform.basis.y + 0.2 * forward

            jump *= desired_jump_power

            # When landing, jump power is effectively lost just stopping the
            # momentum of the body. So, allow up to double the power if needed
            # to allow a jump to happen.
            var speed_into_ground: float = ground_rel_con_velocity.dot(state.transform.basis.y)
            if speed_into_ground < 0.0:
                var extra: Vector3 = state.transform.basis.y * minf(desired_jump_power, -speed_into_ground)
                if forward.is_zero_approx():
                    extra *= 0.6
                else:
                    extra *= 0.8
                jump += extra

            desired_jump_power = 0.0
            has_landed_on_ground_for_jump = false
        elif not force_ground_movement:
            if forward.is_zero_approx():
                jump = state.transform.basis.y
            else:
                jump = 0.8 * state.transform.basis.y + 0.2 * forward
            jump *= desired_jump_power
            desired_jump_power = 0.0

    # Add final friction values
    var friction: Vector3 = ground_friction + air_friction

    state.linear_velocity += (state.step * friction) + jump

    # Add a slip force by projecting gravity along the downhill vector
    if not gravity.is_zero_approx():
        if is_slipping:
            var downhill: Vector3 = ground_normal.cross(gravity).cross(ground_normal).normalized()
            state.linear_velocity += state.step * downhill * downhill.dot(gravity)
        else:
            state.linear_velocity += state.step * gravity

    if spring:
        state.linear_velocity += spring.total_force * state.inverse_mass * state.step
        #print('%.3f | s: %s' % [float(Time.get_ticks_msec()) / 1000.0, spring.total_force * state.inverse_mass])

    if state.linear_velocity.length_squared() < 1e-4:
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
                    state.transform.origin + (Vector3.UP * 0.55),
                    state.linear_velocity,
                    Color.FOREST_GREEN,
                    _velocity_debug_vec,
            )
            _velocity_debug_text = DebugDraw.text(
                    state.transform.origin + (Vector3.UP * 0.55),
                    '%.3f m/s' % linear_speed,
                    Color.FOREST_GREEN,
                    _velocity_debug_text
            )

        if debug_forward:
            var norm: Vector3 = forward
            if not norm.is_zero_approx():
                norm = norm.normalized()
            _forward_debug_vec = DebugDraw.vector(
                    state.transform.origin + (Vector3.UP * 0.5),
                    norm,
                    Color.GREEN_YELLOW,
                    _forward_debug_vec,
                    2.0
            )

        if debug_friction:
            _friction_debug_vec = DebugDraw.vector(
                state.transform.origin + (Vector3.UP * 0.45),
                friction,
                Color.FIREBRICK,
                _friction_debug_vec,
                2.0
            )

## Calculate a ground force using a spring-mass-damper simulation and friction
func _calculate_ground_force(state: PhysicsDirectBodyState3D) -> void:

    if spring and spring.is_colliding():
        if not is_on_floor:
            is_on_floor = true
    else:
        if is_on_floor:
            is_on_floor = false
            is_slipping = false
            ground_normal = Vector3.ZERO
            ground_friction = Vector3.ZERO
            ground_direction = Vector3.ZERO
            ground_velocity = Vector3.ZERO
            ground_rel_con_velocity = Vector3.ZERO
            spring.save_state()
            spring.total_force = Vector3.ZERO
        return

    spring.save_state()

    var ground: Object = spring.get_collider(0)
    var hit_position: Vector3 = spring.get_collision_point(0)
    ground_normal = spring.get_collision_normal(0)

    # Slope angle check
    var floor_cos_theta: float = ground_normal.dot(state.transform.basis.y)

    is_slipping = false
    if floor_cos_theta <= cos(max_slope_angle):
        is_slipping = true
        wall_slide_normal = ground_normal

        # Ignore this contact and recast for a better surface
        var to_ignore: RID = spring.get_collider_rid(0)
        spring.add_exception_rid(to_ignore)
        spring.force_shapecast_update()
        if spring.is_colliding():
            ground_normal = spring.get_collision_normal(0)

            floor_cos_theta = ground_normal.dot(state.transform.basis.y)
            if floor_cos_theta > cos(max_slope_angle):
                spring.save_state()
                is_slipping = false
                has_landed_on_ground_for_jump = true
                ground = spring.get_collider(0)

        spring.remove_exception_rid(to_ignore)
    else:
        has_landed_on_ground_for_jump = true

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
        local_position = hit_position - ground_state.transform.origin
        ground_contact_velocity = ground_state.get_velocity_at_local_position(local_position)

    if ground_contact_velocity.is_zero_approx():
        ground_rel_con_velocity = state.linear_velocity
        ground_velocity = state.linear_velocity.slide(ground_normal)
        ground_friction = friction_coef * -ground_velocity
    else:
        var relative_contact_velocity: Vector3 = ground_contact_velocity - state.linear_velocity

        # Use relative velocity as ground velocity
        ground_rel_con_velocity = -relative_contact_velocity
        ground_velocity = ground_rel_con_velocity.slide(ground_normal)

        # Ground friction in m/s^2
        ground_friction = friction_coef * relative_contact_velocity.slide(ground_normal)

    spring.calculate_force(state.step, ground_rel_con_velocity.dot(spring.direction), desired_height_offset, is_slipping)

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO

    if ground_state:
        # Apply opposing spring force to body, invert ground velocity to push back
        ground_state.apply_force(-1.0 * (spring.total_force + ground_velocity * mass), local_position)

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
