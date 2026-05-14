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
@export var spring_active: bool = true


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
var _spring_debug_force_vec: int = 0
var _spring_debug_shape: int = 0
var _spring_debug_line: int = 0


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


## The body's direction of motion
var linear_direction: Vector3

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

## Ground contact point in global space, is INF when no ground is detected
var ground_position: Vector3

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


var _friction_coef: float
var _combined_restitution: float


func _ready() -> void:

    # Make this body use custom integrator
    custom_integrator = true

    # Setup spring
    if spring:
        spring.enabled = false
        spring.body_rid = get_rid()

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

    # Apply damping forces immediately
    if not is_zero_approx(state.total_linear_damp):
        state.linear_velocity -= state.linear_velocity * state.total_linear_damp * state.step
    if not is_zero_approx(state.total_angular_damp):
        state.angular_velocity -= state.angular_velocity * state.total_angular_damp * state.step

    var local_up: Vector3 = state.transform.basis.y

    var gravity: Vector3 = state.total_gravity * desired_gravity

    _update_ground(state)
    _update_motion(state)

    _calculate_ground_vectors(state)

    # "Air drag"
    # (1/2) * Density * v^2 * Area * Coefficient
    var air_friction: Vector3 = Vector3.ZERO
    if not is_zero_approx(linear_speed):
        var lateral_ratio: float = clampf(lateral_speed / (lateral_speed + vertical_speed), 0.0, 1.0)
        air_friction = (
                0.5 * 1.21 # Fluid density
                * -linear_direction * linear_speed * linear_speed
                # Surface area, rough estimates
                * lerpf(0.09, 0.3, lateral_ratio)
                # Drag coefficient, falling calculated to result in 112m/s terminal speed
                # and lateral to roughly a sprinter's coefficient
                * lerpf(0.0143, 0.65, lateral_ratio)
        ) * state.inverse_mass # NOTE: Proportional to mass!!!

    if (not has_desired_forward) and (not is_slipping) and deceleration > 0.0 and not ground_velocity.is_zero_approx():
            # Stop quickly

            # TODO: Stopping friction is causing weird interactions on slopes.
            #       This must be addressed by trying new ways to calculate it here.
            var lateral_ground: Vector3 = ground_rel_con_velocity.slide(local_up)
            var ground_speed: float = lateral_ground.length()

            var max_stop_speed: float = ground_speed / state.step
            var stop_len: float = minf(deceleration, max_stop_speed)

            ground_friction += (-ground_direction) * stop_len

    # NOTE: Computes and applies spring and ground friction forces from current state
    if spring_active and spring:
        spring.solve_forces(state.step, desired_height_offset, _combined_restitution)

    if debug_enabled and debug_spring and spring_active and spring:
        _spring_debug_force_vec = DebugDraw.vector(
            spring.global_position,
            2.0 * spring.total_force / mass,
            Color.DARK_SLATE_BLUE,
            _spring_debug_force_vec,
            0.1
        )
        var color: Color = Color.LIGHT_GREEN
        var length: float = spring.max_length
        if spring.is_colliding():
            length = spring.length
            color = Color.RED
        var offset: Vector3 = spring.global_basis * (-spring.direction * length)
        _spring_debug_shape = DebugDraw.sphere(
            spring.global_position + offset,
            (spring.shape as SphereShape3D).radius,
            color,
            _spring_debug_shape,
            0.1
        )
        _spring_debug_line = DebugDraw.vector(
            spring.global_position,
            offset,
            color,
            _spring_debug_line,
            0.1
        )

    state.linear_velocity += gravity * state.step

    # When slipping, add an extra force orthogonal to gravity in the downhill direction
    if not gravity.is_zero_approx() and is_slipping:
        var slip: Vector3 = ground_normal.cross(gravity).cross(ground_normal)
        if not slip.is_zero_approx():
            slip = slip.normalized()
            slip = slip * slip.dot(gravity)
            state.linear_velocity += slip.slide(gravity.normalized()) * state.step

    state.linear_velocity += (air_friction + ground_friction) * state.step

    if debug_enabled and is_on_floor:
        var normal_center: Vector3
        if spring_active and spring and spring.contact_point.is_finite():
            normal_center = spring.contact_point
        else:
            normal_center = state.transform.origin
        if debug_normal:
            _normal_debug_vec = DebugDraw.vector(
                    normal_center,
                    ground_normal * 0.5,
                    Color.CORNFLOWER_BLUE,
                    _normal_debug_vec,
                    2.0
            )
        if debug_friction:
            _friction_debug_vec = DebugDraw.vector(
                state.transform.origin + (Vector3.UP * 0.45),
                air_friction + ground_friction,
                Color.FIREBRICK,
                _friction_debug_vec,
                2.0
            )

    # User code to apply additional forces just prior to movement calculations
    # Be nice and update motion values in case user code depends on them
    _update_motion(state)
    _custom_pre_movement_forces(state)

    # If at low speed after all external forces are applied, zero out the velocity
    if state.linear_velocity.length_squared() < 1e-4:
        state.linear_velocity = Vector3.ZERO
    # Roughtly 0.5 degrees per seconds
    if state.angular_velocity.length_squared() < 7.62e-5:
        state.angular_velocity = Vector3.ZERO

    # NOTE: Update again so that movement accelerations can react to any body velocity changes
    #       caused by external forces, such that it may overcome them, like gravity and friction.
    _update_motion(state)

    var forward: Vector3 = Vector3.ZERO
    var speed_in_dir: float = linear_speed
    var limit_in_dir: float = desired_speed
    var accel_multiplier: float = 1.0

    if is_on_floor:

        if has_desired_forward:
            # Stable ground movement, only when not already calculated from steep ground
            if force_ground_movement:
                # NOTE: I hate how this is nested, but a function for it seems overkill
                forward = local_up.cross(desired_direction).cross(ground_normal).normalized()
                speed_in_dir = ground_velocity.dot(forward)
                if is_slipping:
                    var wall_normal: Vector3 = Vector3(wall_slide_normal.x, 0.0, wall_slide_normal.z)
                    if not wall_normal.is_zero_approx():
                        var slip_forward: Vector3 = local_up.cross(desired_direction).cross(local_up)
                        if not slip_forward.is_zero_approx():
                            wall_normal = wall_normal.normalized()
                            forward = slip_forward.normalized()
                            # If forward is against wall, do additional speed reductions and clamp forward to wall
                            if wall_normal.dot(forward) < 0.0:
                                var slip_mult: float = forward.dot(forward.slide(wall_normal))
                                limit_in_dir *= slip_mult
                                accel_multiplier *= slip_mult
                                forward = forward.slide(wall_normal)
                                if not forward.is_zero_approx():
                                    forward = forward.normalized()

            else:
                forward = desired_direction
                speed_in_dir = ground_velocity.dot(forward)

            # Limit forward acceleration
            if (not force_ground_movement) and desired_incline_effect > 0.0:
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
                state.linear_velocity += move_friction * state.step

    elif force_ground_movement:
        # Air control
        if air_control > 0.0 and has_desired_forward:
            forward = local_up.cross(desired_direction).cross(local_up).normalized()
            accel_multiplier *= air_control
    else:
        forward = desired_direction

    # Jumping, reset power to zero when activated
    if desired_jump_power > 0.0:
        var jump: Vector3 = Vector3.ZERO

        if is_on_floor and has_landed_on_ground_for_jump:
            if forward.is_zero_approx():
                jump = 0.6 * local_up + 0.4 * ground_normal
            else:
                jump = 0.8 * local_up + 0.2 * forward

            jump *= desired_jump_power

            # When landing, jump power is effectively lost just stopping the
            # momentum of the body. So, allow up to double the power if needed
            # to allow a jump to happen.
            var speed_into_ground: float = ground_rel_con_velocity.dot(local_up)
            if speed_into_ground < 0.0:
                var extra: Vector3 = local_up * minf(desired_jump_power, -speed_into_ground)
                if forward.is_zero_approx():
                    extra *= 0.6
                else:
                    extra *= 0.8
                jump += extra

            desired_jump_power = 0.0
            has_landed_on_ground_for_jump = false
        elif not force_ground_movement:
            if forward.is_zero_approx():
                jump = local_up
            else:
                jump = 0.8 * local_up + 0.2 * forward
            jump *= desired_jump_power
            desired_jump_power = 0.0

        state.linear_velocity += jump

    if is_on_floor:
        # NOTE: Should be updated using new velocity, it is a little wrong like this
        speed_in_dir = ground_velocity.dot(forward)
    else:
        speed_in_dir = state.linear_velocity.dot(forward)

    if speed_in_dir < limit_in_dir:
        forward *= minf(acceleration * accel_multiplier, maxf(limit_in_dir - speed_in_dir, 0.0) / state.step)
        state.linear_velocity += forward * state.step

    _update_motion(state)

    if debug_enabled:
        var vector_pos: Vector3 = state.transform.origin + (local_up * 0.5)
        if debug_velocity:
            var vel_pos: Vector3 = vector_pos + (Vector3.UP * 0.05)
            _velocity_debug_vec = DebugDraw.vector(
                    vel_pos,
                    state.linear_velocity,
                    Color.FOREST_GREEN,
                    _velocity_debug_vec,
            )
            _velocity_debug_text = DebugDraw.text(
                    vel_pos,
                    '%.3f m/s' % linear_speed,
                    Color.FOREST_GREEN,
                    24.0,
                    _velocity_debug_text
            )

        if debug_forward:
            var norm: Vector3 = forward
            if not norm.is_zero_approx():
                norm = norm.normalized()
            _forward_debug_vec = DebugDraw.vector(
                    vector_pos,
                    norm,
                    Color.GREEN_YELLOW,
                    _forward_debug_vec,
                    2.0
            )

func _update_motion(state: PhysicsDirectBodyState3D) -> void:
    linear_speed = state.linear_velocity.length_squared()
    if not is_zero_approx(linear_speed):
        linear_speed = sqrt(linear_speed)
        linear_direction = state.linear_velocity / linear_speed
    else:
        linear_speed = 0.0
        linear_direction = Vector3.ZERO
    vertical_velocity = state.transform.basis.y * state.transform.basis.tdoty(state.linear_velocity)
    vertical_speed = vertical_velocity.length()
    lateral_speed = linear_speed - vertical_speed

func _update_ground(state: PhysicsDirectBodyState3D) -> void:

    is_on_floor = false
    is_slipping = false
    ground_normal = Vector3.ZERO
    ground_position = Vector3.INF

    if (not spring_active) or (not spring):
        return

    var local_up: Vector3 = state.transform.basis.y

    spring.cast()
    spring.save_state()
    is_on_floor = spring.is_colliding()
    ground_position = spring.contact_point

    # If spring hits nothing, stop here, do not risk raycast discovering ground
    if not is_on_floor:
        return

    var spring_cos_theta: float = local_up.dot(spring.normal)

    # Raycast for a better ground normal
    var space := state.get_space_state()
    var query := PhysicsRayQueryParameters3D.new()

    var offset: Vector3 = (-spring.direction) * (spring.max_length + (spring.shape as SphereShape3D).radius)

    query.from = spring.global_position
    query.to = spring.global_position + (spring.global_basis * offset)
    query.collision_mask = spring.collision_mask
    query.exclude = [get_rid()]

    var hit: Dictionary = space.intersect_ray(query)
    var hit_ignore: RID
    var ray_cos_theta: float = 0.0

    if hit:
        hit_ignore = hit.rid
        ray_cos_theta = local_up.dot(hit.normal)

    var floor_cos_theta: float
    var best_ground_mode: PhysicsServer3D.BodyMode

    if spring_cos_theta >= ray_cos_theta:
        ground_normal = spring.normal
        best_ground_mode = spring.other_mode
        floor_cos_theta = spring_cos_theta
    else:
        ground_normal = hit.normal
        best_ground_mode = PhysicsServer3D.body_get_mode(hit.rid)
        floor_cos_theta = ray_cos_theta

    if floor_cos_theta > cos(max_slope_angle):
        has_landed_on_ground_for_jump = true
        return

    is_slipping = true
    wall_slide_normal = ground_normal

    # If the best ground was a non-static body, stop here.
    # Otherwise, recast everything ignoring their respective first hits
    if best_ground_mode != PhysicsServer3D.BodyMode.BODY_MODE_STATIC:
        return

    # Do not change the spring interaction unless the other is static
    # This ensures it will apply forces to dynamic bodies on the ground
    var test_new_floors: bool = false
    if spring.other_mode == PhysicsServer3D.BodyMode.BODY_MODE_STATIC:
        var spring_ignore: RID = spring.other_rid
        spring.add_exception_rid(spring_ignore)
        spring.cast()
        # Must be a static body for recasting
        if (
                    spring.is_colliding()
                and (PhysicsServer3D.body_get_mode(spring.get_collider_rid(0)) == PhysicsServer3D.BodyMode.BODY_MODE_STATIC)
        ):
            var new_spring_cos_theta = local_up.dot(spring.get_collision_normal(0))

            if new_spring_cos_theta > spring_cos_theta:
                spring_cos_theta = new_spring_cos_theta
                spring.save_state() # Apply forces from this body
                test_new_floors = true
        spring.remove_exception_rid(spring_ignore)

    if hit_ignore:
        query.exclude = [get_rid(), hit_ignore]
        var new_hit: Dictionary = space.intersect_ray(query)
        # Must be a static body for recasting
        if (
                    new_hit
                and (PhysicsServer3D.body_get_mode(new_hit.rid) == PhysicsServer3D.BodyMode.BODY_MODE_STATIC)
        ):
            var new_ray_cos_theta: float = local_up.dot(new_hit.normal)
            if new_ray_cos_theta > ray_cos_theta:
                ray_cos_theta = new_ray_cos_theta
                hit = new_hit
                test_new_floors = true

    if not test_new_floors:
        return

    if spring_cos_theta >= ray_cos_theta:
        ground_normal = spring.normal
        floor_cos_theta = spring_cos_theta
    else:
        ground_normal = hit.normal
        floor_cos_theta = ray_cos_theta

    if floor_cos_theta > cos(max_slope_angle):
        is_slipping = false
        has_landed_on_ground_for_jump = true
        return

    wall_slide_normal = ground_normal


## Calculate ground vectors from the current ground state
func _calculate_ground_vectors(state: PhysicsDirectBodyState3D) -> void:

    ground_friction = Vector3.ZERO
    ground_direction = Vector3.ZERO
    ground_velocity = Vector3.ZERO
    ground_rel_con_velocity = Vector3.ZERO

    if not is_on_floor:
        return

    var ground_rid: RID = spring.other_rid
    if (not ground_rid) and is_on_floor:
        breakpoint
    var hit_position: Vector3 = spring.contact_point

    var ground_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(ground_rid)

    var rid: RID = get_rid()

    if ground_state:
        _friction_coef = absf(minf(
                PhysicsServer3D.body_get_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION),
                PhysicsServer3D.body_get_param(ground_rid, PhysicsServer3D.BODY_PARAM_FRICTION)
        ))
        _combined_restitution = clampf(
                  PhysicsServer3D.body_get_param(rid, PhysicsServer3D.BODY_PARAM_BOUNCE)
                + PhysicsServer3D.body_get_param(ground_rid, PhysicsServer3D.BODY_PARAM_BOUNCE),
                0.0, 1.0
        )
    else:
        _friction_coef = absf(PhysicsServer3D.body_get_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION))
        _combined_restitution = clampf(
                PhysicsServer3D.body_get_param(rid, PhysicsServer3D.BODY_PARAM_BOUNCE),
                0.0, 1.0
        )

    var ground_contact_velocity: Vector3
    if ground_state:
        ground_contact_velocity = ground_state.get_velocity_at_local_position(hit_position - ground_state.transform.origin)
    else:
        ground_contact_velocity = Vector3.ZERO

    ground_rel_con_velocity = state.linear_velocity - ground_contact_velocity
    ground_velocity = ground_rel_con_velocity.slide(state.transform.basis.y).slide(ground_normal)
    ground_friction = _friction_coef * -ground_velocity

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO


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

## For custom forces that should be applied just before movement
@warning_ignore("unused_parameter")
func _custom_pre_movement_forces(state: PhysicsDirectBodyState3D) -> void:
    pass
