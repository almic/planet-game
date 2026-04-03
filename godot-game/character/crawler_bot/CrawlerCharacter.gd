@tool
class_name CrawlerCharacter extends CharacterController


@export_range(0.01, 8.0, 0.01, 'or_greater')
var max_speed: float = 3.0

@export_range(0.0, 30.0, 0.1, 'or_greater', 'radians_as_degrees')
var max_pitch: float = deg_to_rad(12.0)

@export_range(0.0, 360.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rotation_acceleration: float = deg_to_rad(270.0)

## Maximum rotation speed when turning
@export_range(0.1, 180.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rotation_rate: float = deg_to_rad(180.0)

@export_range(0.1, 1.0, 0.01, 'or_greater')
var rotation_overshoot: float = 0.2

@export var leg_ik: IterateIK3D


@export_group('Leg Parameters', 'body')

## How far off the ground to keep the body's center of mass
@export_range(0.0, 0.5, 0.01, 'or_greater', 'suffix:m')
var body_height_offset: float = 0.5

## How for the body "settles" when affected by gravity, reduces as the body
## becomes parallel to gravity.
@export_range(0.0, 0.2, 0.01, 'or_greater', 'suffix:m')
var body_gravity_offset: float = 0.1

## Stiffness of the spring used to offset the body from the ground
@export_range(0.01, 2.0, 0.01, 'or_greater')
var body_height_spring_stiffness: float = 1.6

## Damping of the spring used to offset the body from the ground
@export_range(0.01, 1.0, 0.01, 'or_greater')
var body_height_spring_damping: float = 0.8

## Percentage of total legs necessary to lift the body. Should not be higher
## than 0.5!
@export_range(0.0, 1.0, 0.01)
var body_leg_mass_ratio: float = 0.5

## How much effective acceleration legs can apply to the body. Should be just
## enough to be stable while being pushed and entering extreme inclines.
@export_range(0.01, 30.0, 0.01, 'or_greater')
var body_max_leg_force: float = 20.0

@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false


var legs: Array[CrawlerLeg]
var skeleton: Skeleton3D

var target_position: Vector3 = Vector3.INF
var target_direction: Vector3 = Vector3.INF

var is_stepping: bool:
    get():
        return has_desired_forward or has_desired_rotation

var has_desired_rotation: bool = false
var grounded_leg_count: int = 0
var grounded_leg_avg_displacement: float = 0.0
var leg_update_data: PackedVector3Array


func _ready() -> void:
    super._ready()

    manual_input_handling = true
    skeleton = leg_ik.get_skeleton()

    # Load legs from children
    legs.assign(find_children('', 'CrawlerLeg'))

    var index: int = 0
    for leg in legs:
        leg.body = self
        leg.index = index

        index += 1

        # Copy collision mask to casters
        leg.shape_cast.collision_mask = collision_mask

    leg_update_data.resize(index * 2)

    # Initialize legs
    for leg in legs:
        leg.setup()

    leg_ik.active = not Engine.is_editor_hint()

    skeleton.skeleton_updated.connect(update_leg_transforms)

func update_leg_transforms() -> void:
    for leg in legs:
        leg.update_ground_leg_transform()

func _handle_input() -> void:

    if target_position.is_finite() and (target_position - position).length_squared() > 4.0:
        target_direction = (target_position - position).normalized()
        desired_direction = (target_position - position).normalized()
        desired_speed = max_speed
    elif not desired_direction.is_zero_approx():
        desired_direction = Vector3.ZERO
        desired_speed = 0.0
        target_position = Vector3.INF


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    _handle_input()

    _update_legs(state)

    super._integrate_forces(state)

func _update_legs(state: PhysicsDirectBodyState3D) -> void:

    grounded_leg_count = 0
    ground_normal = Vector3.ZERO

    for leg in legs:
        leg.update(state)

        if leg.is_grounded:
            grounded_leg_count += 1
            ground_normal += leg.ground_normal

    if grounded_leg_count > 0:
        grounded_leg_avg_displacement /= grounded_leg_count
        ground_normal /= grounded_leg_count

        if ground_normal.is_zero_approx():
            ground_normal = state.transform.basis.y
        else:
            ground_normal = ground_normal.normalized()

func _calculate_ground_force(state: PhysicsDirectBodyState3D) -> void:

    if grounded_leg_count > 0:
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
        return

    ground_rel_con_velocity = state.linear_velocity
    ground_velocity = ground_rel_con_velocity.slide(ground_normal)
    ground_friction = Vector3.ZERO

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO


func _custom_pre_movement_forces(state: PhysicsDirectBodyState3D) -> void:
    _solve_leg_offsets(state)

    _solve_rotation(state)

func _solve_leg_offsets(state: PhysicsDirectBodyState3D) -> void:
    if grounded_leg_count < 1:
        return

    var total_gravity: Vector3 = state.total_gravity * desired_gravity
    var gravity_direction: Vector3 = Vector3.ZERO
    if not state.total_gravity.is_zero_approx():
        gravity_direction = state.total_gravity.normalized()

    var leg_ratio: float = float(grounded_leg_count) / float(legs.size())
    var leg_mass: float = mass / legs.size()
    var shared_mass: float = mass / grounded_leg_count
    if not is_zero_approx(body_leg_mass_ratio):
        shared_mass = minf(shared_mass, mass / (legs.size() * (1.0 - body_leg_mass_ratio)))

    var max_force: float = body_max_leg_force * leg_mass

    var iteration: int = 0
    # NOTE: 2 is probably enough, but I chose 3 so that it definitely would be accurate
    var max_iterations: int = 3
    var sub_step: float = state.step / max_iterations
    var old_transform: Transform3D = state.transform

    var old_angular: Vector3 = state.angular_velocity

    while iteration < max_iterations:
        iteration += 1

        grounded_leg_avg_displacement = 0.0

        # Update the body virtually
        state.transform.origin += state.linear_velocity * sub_step
        var angular_len: float = state.angular_velocity.length()
        if not is_zero_approx(angular_len):
            state.transform.basis = state.transform.basis.rotated(state.angular_velocity / angular_len, angular_len * sub_step)
        var spring_direction: Vector3 = state.transform.basis.y

        var gravity_alignment: float = state.transform.basis.tdoty(gravity_direction) * desired_gravity
        var total_height_offset: float = body_height_offset + body_gravity_offset * gravity_alignment

        for leg in legs:
            if not leg.is_grounded:
                continue

            var global_attachment: Vector3 = state.transform * leg.attachment_point

            # These lines copied from CrawlerLeg
            var attachment_plane: Plane = Plane(-state.transform.basis.y, global_attachment)
            leg.ground_offset = attachment_plane.distance_to(leg.ground_point) - total_height_offset

            grounded_leg_avg_displacement += absf(leg.ground_offset)

            var spring_midpoint: Vector3 = (0.5 * (leg.ground_point + global_attachment)) - state.transform.origin
            leg_update_data[leg.index * 2] = spring_midpoint
            leg_update_data[leg.index * 2 + 1] = state.get_velocity_at_local_position(spring_midpoint)

        grounded_leg_avg_displacement /= grounded_leg_count

        for leg in legs:
            if not leg.is_grounded:
                continue

            var offset: float = leg.ground_offset
            offset = signf(offset) * minf(absf(offset), grounded_leg_avg_displacement)

            var spring_midpoint: Vector3 = leg_update_data[leg.index * 2]
            var local_velocity: Vector3 = leg_update_data[leg.index * 2 + 1]
            var rel_ground_velocity: Vector3 = local_velocity - leg.ground_velocity

            var speed: float = spring_direction.dot(rel_ground_velocity)

            var spring_force: float = 100.0 * body_height_spring_stiffness * -offset * shared_mass
            var damp_force: float = 10.0 * body_height_spring_damping * -speed * shared_mass
            var total_force: float = clampf(spring_force + damp_force, -max_force, max_force)

            var force_vec: Vector3 = (total_force * spring_direction) - (total_gravity * leg_mass)

            state.apply_impulse(
                force_vec * sub_step,
                spring_midpoint
            )

            var ground_state := PhysicsServer3D.body_get_direct_state(leg.ground_body)
            if ground_state:
                ground_state.apply_impulse(
                    -force_vec * sub_step,
                    (spring_midpoint + state.transform.origin) - ground_state.transform.origin
                )

        state.angular_velocity = state.angular_velocity.move_toward(old_angular, rotation_acceleration * leg_ratio * sub_step)

    # Reset changes to the transform
    state.transform = old_transform


func _solve_rotation(state: PhysicsDirectBodyState3D) -> void:

    var can_do_yaw: bool = target_direction.is_finite()
    for leg in legs:
        if can_do_yaw and (not leg.is_comfortable) and (not leg.is_moving):
            can_do_yaw = false

    has_desired_rotation = false

    # Must have at least 1 leg grounded to perform rotation
    if grounded_leg_count == 0:
        # TODO: damp rotation as if by air friction
        return

    var leg_count: int = legs.size()
    var grounded_leg_factor: float = float(grounded_leg_count) / float(leg_count)

    var preferred_forward: Vector3
    var preferred_right: Vector3

    var main_legs: Array[CrawlerLeg] = [
        legs[0], legs[1],
        legs[leg_count - 2], legs[leg_count - 1]
    ]
    var ground_points: PackedVector3Array
    ground_points.resize(4)

    var using_rest_point: bool = false
    var using_ground_points: bool = true
    for i in range(4):
        var leg: CrawlerLeg = main_legs[i]
        if leg.is_grounded:
            ground_points[i] = leg.target.position
        elif leg.is_moving:
            ground_points[i] = leg.step_target
        elif using_rest_point:
            # Cannot use more than 1 rest point, use current orientation
            preferred_forward = -state.transform.basis.z
            preferred_right = state.transform.basis.x
            using_ground_points = false
            break
        else:
            using_rest_point = true
            ground_points[i] = leg.target_global_rest

    if using_ground_points:
        preferred_forward = (
                  (ground_points[0] - ground_points[2])
                + (ground_points[1] - ground_points[3])
        ).normalized()
        preferred_right = (
                  (ground_points[1] - ground_points[0])
                + (ground_points[3] - ground_points[2])
        ).normalized()

    var preferred_up: Vector3 = preferred_right.cross(preferred_forward).normalized()

    var current_forward: Vector3 = -state.transform.basis.z
    var current_right: Vector3 = state.transform.basis.x

    var yaw: float
    if can_do_yaw:
        # Only yaw when this is true:
        # r > pow(0.03125 - 0.03125 * cos_theta, 0.25)
        # NOTE: xz_dot == r
        var xz_dot: float = 1.0 - absf(preferred_up.dot(target_direction))
        var cos_theta: float = preferred_forward.dot(target_direction)
        if xz_dot > pow(0.03125 - 0.03125 * cos_theta, 0.25):
            yaw = current_forward.signed_angle_2(target_direction, preferred_up)
            # NOTE: about 0.5 degrees
            if absf(yaw) > 8.7e-3:
                has_desired_rotation = true

    var roll: float = current_right.signed_angle_2(preferred_right, -preferred_forward)
    var pitch: float = current_forward.signed_angle_2(preferred_forward, preferred_right)

    var angular: Vector3 = Vector3(pitch, yaw, roll)
    angular.x = 0.0
    angular.z = 0.0

    var max_angular: Vector3 = angular / state.step
    var limited_angular: Vector3 = angular.sign() * max_angular.abs().minf(rotation_rate * (1.0 / rotation_overshoot))
    var target_angular: Vector3 = state.transform.basis * limited_angular

    state.angular_velocity = state.angular_velocity.move_toward(
            target_angular * rotation_overshoot,
            state.step * rotation_acceleration * grounded_leg_factor
    )

    # NOTE: roughly 0.5 degrees per second
    if target_angular.is_zero_approx() and state.angular_velocity.length_squared() < 8e-5:
        state.angular_velocity = Vector3.ZERO
        if not has_desired_rotation:
            # Low angular velocity, facing the target, clear target
            target_direction = Vector3.INF
