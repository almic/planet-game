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

## Stores the delta time for the current physics update
var delta_time: float
## Stores the reference to this body state for the current physics update
var phys_state: PhysicsDirectBodyState3D

var desired_direction: Vector3 = Vector3.ZERO
var desired_speed: float = 0.0
var desired_incline_effect: float = 1.0
var desired_jump_power: float = 0.0
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

## Velocity of this body along the plane defined by the ground normal
var ground_velocity: Vector3

## Direction of this body along the plane of the ground
var ground_direction: Vector3

## Speed along the ground, or the length of ground_velocity
var ground_speed: float

## Calculated ground friction force
var ground_friction: Vector3

## Relative contact velocity with the ground, including velocity into the surface
var ground_rel_con_velocity: Vector3

## Calculated wall slide normal, only use when is_slipping is true
var wall_slide_normal: Vector3


func _ready() -> void:

    # Make this body use custom integrator
    custom_integrator = true

    # Setup spring
    if spring:
        spring.pick_collisions_function = pick_ground


## Implement per controller, called when input should be read for movement.
## If your controller has a camera connect to mouse movement, you should handle
## that directly in _process() instead.
func _handle_input() -> void:
    pass


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    phys_state = state
    delta_time = state.step

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

    state.linear_velocity += gravity * state.step

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

    state.linear_velocity += air_friction * state.step

    # When slipping, add an extra force orthogonal to gravity in the downhill direction
    if not gravity.is_zero_approx() and is_slipping:
        var slip: Vector3 = ground_normal.cross(gravity).cross(ground_normal)
        if not slip.is_zero_approx():
            slip = slip.normalized()
            slip = slip * slip.dot(gravity)
            state.linear_velocity += slip.slide(gravity.normalized()) * state.step

    if debug_enabled and is_on_floor:
        if debug_normal:
            _normal_debug_vec = DebugDraw.vector(
                    ground_position,
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
                speed_in_dir = ground_rel_con_velocity.dot(forward)
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
                speed_in_dir = ground_rel_con_velocity.dot(forward)

            # Limit forward acceleration
            if force_ground_movement and desired_incline_effect > 0.0:
                var slope_cos_theta: float = local_up.dot(forward)
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
            if not is_slipping:
                # NOTE: this should allow maintaining high speed and changing direction, but only
                # with long turns and still has some loss... you could only recover when
                # speed_in_dir < limit_in_dir, and clamp to the limit, but this just sounds fun...
                var recovery: Vector3 = state.inverse_mass * _calculate_friction_recovery(forward)
                if debug_enabled and debug_friction:
                    _friction_movement_debug_vec = DebugDraw.vector(
                            state.transform.origin + (Vector3.UP * 0.45),
                            recovery,
                            Color.DARK_GREEN,
                            _friction_movement_debug_vec,
                            2.0
                    )
                state.linear_velocity += recovery * state.step

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
        speed_in_dir = ground_rel_con_velocity.dot(forward)
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

    if (not spring) or (not spring.enabled):
        return

    is_on_floor = spring.is_colliding()

    # If spring hits nothing, stop here, do not risk raycast discovering ground
    if not is_on_floor:
        return

    # Compute a ground position and normal using the best normal
    var global_up: Vector3 = state.transform.basis.y # technically global, too
    var best_cos_theta: float = -INF
    for i in range(spring.get_contact_body_count()):
        var normal: Vector3 = -spring.get_contact_normal(i)
        if normal.dot(global_up) > best_cos_theta:
            ground_normal = normal
            ground_position = spring.get_contact_average_point(i)

    if best_cos_theta >= cos(max_slope_angle):
        has_landed_on_ground_for_jump = true
        return

    is_slipping = true
    wall_slide_normal = ground_normal

@warning_ignore("unused_parameter")
func pick_ground(
        rid_list: Array[RID],
        spring_fraction_list: PackedFloat32Array,
        average_contact_point_list: PackedVector3Array,
        average_normal_list: PackedVector3Array
) -> Array[RID]:
    var cos_preferred: float = cos(max_slope_angle)
    var global_up: Vector3
    if phys_state:
        global_up = phys_state.transform.basis.y
    else:
        global_up = Vector3.UP
    var preferred: Array[RID] = []
    for i in range(average_normal_list.size()):
        var normal: Vector3 = -average_normal_list[i]
        if normal.dot(global_up) >= cos_preferred:
            preferred.append(rid_list[i])

    if preferred.size() > 0:
        return preferred

    return rid_list

## Calculate ground vectors from the current ground state
func _calculate_ground_vectors(state: PhysicsDirectBodyState3D) -> void:
    const STATIC_MASS: float = 10000.0

    ground_friction = Vector3.ZERO
    ground_direction = Vector3.ZERO
    ground_velocity = Vector3.ZERO
    ground_rel_con_velocity = Vector3.ZERO
    ground_speed = 0.0

    if not is_on_floor:
        return

    var inv_effective_mass: float = 0.0

    for i in range(spring.get_contact_body_count()):
        var ground_rid: RID = spring.get_contact_body_rid(i)
        var ground_mass: float
        if PhysicsServer3D.body_get_mode(ground_rid) == PhysicsServer3D.BODY_MODE_STATIC:
            ground_mass = STATIC_MASS
        else:
            ground_mass = PhysicsServer3D.body_get_param(ground_rid, PhysicsServer3D.BODY_PARAM_MASS)

        inv_effective_mass += 1.0 / ground_mass
        ground_friction += spring.get_contact_friction(i)

    var effective_mass: float = 1.0 / inv_effective_mass

    for i in range(spring.get_contact_body_count()):
        var ground_rid: RID = spring.get_contact_body_rid(i)
        var hit_position: Vector3 = spring.get_contact_average_point(i)
        var ground_state := PhysicsServer3D.body_get_direct_state(ground_rid)
        var ground_contact_velocity: Vector3
        var ground_mass: float
        if PhysicsServer3D.body_get_mode(ground_rid) == PhysicsServer3D.BODY_MODE_STATIC:
            ground_mass = STATIC_MASS
            ground_contact_velocity = Vector3.ZERO
        else:
            ground_mass = PhysicsServer3D.body_get_param(ground_rid, PhysicsServer3D.BODY_PARAM_MASS)
            ground_contact_velocity = ground_state.get_velocity_at_local_position(hit_position - ground_state.transform.origin)

        # Ground velocity contribution shared by mass proportion, higher mass contribute more
        ground_rel_con_velocity += (1.0 - (effective_mass / ground_mass)) * (state.linear_velocity - ground_contact_velocity)

    ground_velocity = ground_rel_con_velocity.slide(ground_normal)

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO

    ground_speed = ground_velocity.dot(ground_direction)


## Calculate recovery acceleration from applied ground friction for turning/ changing direction.
## NOTE: this is a force, so it must be multiplied by the main body's inverse mass to get acceleration
func _calculate_friction_recovery(forward: Vector3) -> Vector3:
    var recovery: Vector3 = Vector3.ZERO

    for i in range(spring.get_contact_body_count()):
        var friction: Vector3 = spring.get_contact_friction(i)
        if friction.is_zero_approx():
            continue

        var cos_theta: float = clampf(forward.dot(-friction.normalized()), -1.0, 1.0)

        # Full recovery if wish direction and friction match
        if cos_theta == 1.0:
            recovery -= friction
            continue

        var angle: float = acos(cos_theta)

        # Retain some speed when turning, multiplier is per 15* of difference
        var keep: float = pow(clampf(turning_retention, 0.001, 0.943), angle * (12.0 / PI))

        # Allow counter-strafing at "half" the normal rate, reduces jumpy feeling
        if cos_theta <= 0.0:
            keep *= keep

        recovery -= friction * keep

    return recovery

## For custom forces that should be applied just before movement
@warning_ignore("unused_parameter")
func _custom_pre_movement_forces(state: PhysicsDirectBodyState3D) -> void:
    pass
