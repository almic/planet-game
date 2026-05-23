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

@export var skeleton: Skeleton3D
@export var physical_skeleton: PhysicalSkeleton
@export var leg_ik: IterateIK3D

## The number of grounded legs necessary for jumping
@export_range(1, 8, 1, 'or_less')
var legs_needed_for_jump: int = 3

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

## Percentage of total legs necessary to lift the body.
@export_range(0.0, 1.0, 0.01)
var body_leg_mass_ratio: float = 0.5

## How much effective acceleration legs can apply to the body. Should be just
## enough to be stable while being pushed and entering extreme inclines.
@export_range(0.01, 30.0, 0.01, 'or_greater')
var body_max_leg_force: float = 20.0

@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false

@export var debug_leg_polygon: bool = false
var _debug_leg_polyline: int = 0

@export var debug_leg_gravity: bool = false
var _debug_leg_gravity_vec: int = 0


var legs: Array[CrawlerLeg]

var target_position: Vector3 = Vector3.INF
var target_direction: Vector3 = Vector3.INF

var is_stepping: bool:
    get():
        return has_desired_forward or has_desired_rotation

var has_desired_rotation: bool = false
var grounded_leg_count: int = 0
var grounded_leg_avg_displacement: float
var leg_update_data: PackedVector3Array
var leg_polygon: PackedVector2Array
var leg_gravity_power: PackedFloat64Array


func _ready() -> void:
    super._ready()

    # Load legs from children
    legs.assign(find_children('', 'CrawlerLeg'))

    var count: int = legs.size()
    for i in range(count):
        var leg: CrawlerLeg = legs[i]
        leg.body = self
        leg.index = i

        # Copy collision mask to casters
        leg.shape_cast.collision_mask = collision_mask

    if Engine.is_editor_hint():
        return

    leg_update_data.resize(count * 3)
    leg_gravity_power.resize(count)
    leg_gravity_power.fill(0.0)

    # Collect leg rigid bodies to ignore for shape casts
    var child_bodies: Array[RID]
    for body in find_children('', 'CollisionObject3D'):
        if body is CollisionObject3D:
            child_bodies.append(body.get_rid())

    # Get the chain end bones for each leg target
    var target_bones: Dictionary = {}
    for setting in range(leg_ik.setting_count):
        target_bones.set(leg_ik.get_target_node(setting), leg_ik.get_end_bone(setting))

    # Collect target nodes for ground bones
    var ground_targets: Dictionary[int, Node3D] = {}
    var attachments: Array[ModifierBoneTarget3D]
    attachments.assign(skeleton.find_children('', 'ModifierBoneTarget3D'))
    for attach in attachments:
        var bodies: Array[RigidBody3D]
        bodies.assign(attach.find_children('', 'RigidBody3D', false))
        if bodies.size() == 0:
            continue
        ground_targets.set(
            attach.bone,
            bodies[0]
        )

    # Initialize legs
    for leg in legs:
        leg.setup(
                ground_targets,
                target_bones.get(leg_ik.get_path_to(leg.target)),
                child_bodies
        )

    leg_ik.active = not Engine.is_editor_hint()

    physical_skeleton.set_ik_modifier(leg_ik)
    skeleton.skeleton_updated.connect(update_leg_transforms)

    desired_surface_friction = 0.0


func update_leg_transforms() -> void:
    for leg in legs:
        leg.update_ground_leg_transform()

func damage(source: Object, amount: float, hit_point: Vector3) -> void:
    print('Took %f damage from %s at position %s' % [amount, source.name, str(hit_point)])


func _handle_input() -> void:

    if target_position.is_finite() and (target_position - position).length_squared() > 4.0:
        target_direction = (target_position - position).normalized()
        desired_direction = (target_position - position).normalized()
        desired_speed = max_speed
    elif not desired_direction.is_zero_approx():
        desired_direction = Vector3.ZERO
        desired_speed = 0.0
        target_position = Vector3.INF

func _update_ground(state: PhysicsDirectBodyState3D) -> void:

    is_on_floor = false
    is_slipping = false
    ground_normal = Vector3.ZERO
    ground_position = Vector3.ZERO
    grounded_leg_count = 0

    for leg in legs:
        leg.pre_update(state)

    for leg in legs:
        leg.check_early_step()

    for leg in legs:
        leg.update(state)

        # At this point, all legs have decided if they want to apply ground forces or not
        if leg.apply_ground_forces:
            grounded_leg_count += 1
            ground_normal += leg.ground_normal
            ground_position += leg.ground_point

    if grounded_leg_count > 0:
        is_on_floor = true
        ground_normal /= grounded_leg_count
        ground_position /= grounded_leg_count

        if ground_normal.is_zero_approx():
            ground_normal = state.transform.basis.y
        else:
            ground_normal = ground_normal.normalized()

        if grounded_leg_count >= legs_needed_for_jump:
            has_landed_on_ground_for_jump = true
    else:
        ground_position = Vector3.INF

func _calculate_ground_vectors(state: PhysicsDirectBodyState3D) -> void:

    ground_direction = Vector3.ZERO
    ground_velocity = Vector3.ZERO
    ground_rel_con_velocity = Vector3.ZERO

    if not is_on_floor:
        return

    # Gather relative velocity from all legs, using last gravity power
    var max_leg_mass: float
    if is_zero_approx(body_leg_mass_ratio):
        max_leg_mass = mass
    else:
        max_leg_mass = mass / (legs.size() * body_leg_mass_ratio)

    for leg in legs:
        if not leg.is_grounded:
            continue

        # Reduce applied force when leg should not be "holding" the ground
        var power: float = minf(mass * leg_gravity_power[leg.index], max_leg_mass)
        if not leg.apply_ground_forces:
            power *= 0.1

        var leg_ground_velocity: Vector3 = leg.ground_rel_con_velocity.slide(leg.ground_normal)
        ground_rel_con_velocity += leg.ground_rel_con_velocity
        ground_velocity += leg_ground_velocity

        # Apply angular forces here
        var leg_force: Vector3 = 0.0 * power * leg.ground_rel_con_velocity * state.inverse_mass
        state.angular_velocity += (
              state.inverse_inertia_tensor
            * (leg.ground_point - state.transform.origin - state.center_of_mass).cross(leg_force)
        ) * state.step

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

    var rid: RID = get_rid()

    var total_gravity: Vector3 = state.total_gravity * desired_gravity
    var gravity_direction: Vector3 = Vector3.ZERO
    if not state.total_gravity.is_zero_approx():
        gravity_direction = state.total_gravity.normalized()

    var leg_ratio: float = float(grounded_leg_count) / float(legs.size())
    var leg_mass: float = mass / legs.size()
    var max_leg_mass: float

    if is_zero_approx(body_leg_mass_ratio):
        max_leg_mass = mass
    else:
        max_leg_mass = mass / (legs.size() * body_leg_mass_ratio)

    var shared_mass: float = minf(mass / grounded_leg_count, max_leg_mass)

    var max_force: float = body_max_leg_force * leg_mass

    var iteration: int = 0
    # NOTE: 2 is probably enough, but I chose 3 so that it definitely would be accurate
    var max_iterations: int = 3
    var sub_step: float = state.step / max_iterations
    var old_transform: Transform3D = state.transform

    var old_angular: Vector3 = state.angular_velocity

    var total_grav_vec: Vector3 = Vector3.ZERO

    while iteration < max_iterations:
        iteration += 1

        grounded_leg_avg_displacement = 0.0

        var spring_direction: Vector3 = state.transform.basis.y

        var gravity_alignment: float = state.transform.basis.tdoty(gravity_direction) * desired_gravity
        var total_height_offset: float = body_height_offset + body_gravity_offset * gravity_alignment

        var poly_front_index: int = 0
        if debug_enable and debug_leg_polygon:
            leg_polygon.clear()

        var body_plane: Plane = Plane(state.transform.basis.y, state.transform.origin + state.center_of_mass)

        for leg in legs:
            if not leg.apply_ground_forces:
                continue

            var global_attachment: Vector3 = state.transform * leg.attachment_point

            # These lines copied from CrawlerLeg
            var attachment_plane: Plane = Plane(-state.transform.basis.y, global_attachment)
            leg.ground_offset = attachment_plane.distance_to(leg.ground_point) - total_height_offset

            grounded_leg_avg_displacement += absf(leg.ground_offset)

            var spring_midpoint: Vector3 = (0.5 * (leg.ground_point + global_attachment)) - state.transform.origin
            leg_update_data[leg.index * 3] = spring_midpoint
            leg_update_data[leg.index * 3 + 1] = state.get_velocity_at_local_position(spring_midpoint)
            leg_update_data[leg.index * 3 + 2] = body_plane.project(spring_midpoint + state.transform.origin) - state.transform.origin

            if debug_enable and debug_leg_polygon:
                var plane_point: Vector3 = body_plane.project(leg.ground_point) - (state.transform.origin + state.center_of_mass)
                var polygon_point: Vector2 = Vector2(state.transform.basis.tdotx(plane_point), state.transform.basis.tdotz(plane_point))
                leg_polygon.insert(poly_front_index, polygon_point)
                if leg.is_left:
                    poly_front_index += 1

        grounded_leg_avg_displacement /= grounded_leg_count

        _calculate_leg_gravity_power(state)

        for leg in legs:
            if not leg.apply_ground_forces:
                continue

            var offset: float = leg.ground_offset
            offset = signf(offset) * minf(absf(offset), grounded_leg_avg_displacement)

            var spring_midpoint: Vector3 = leg_update_data[leg.index * 3]
            var local_velocity: Vector3 = leg_update_data[leg.index * 3 + 1]
            var anti_gravity_point: Vector3 = leg_update_data[leg.index * 3 + 2]
            var rel_ground_velocity: Vector3 = local_velocity - leg.ground_velocity

            var speed: float = spring_direction.dot(rel_ground_velocity)

            var spring_force: float = 100.0 * body_height_spring_stiffness * -offset * shared_mass
            var damp_force: float = 10.0 * body_height_spring_damping * -speed * shared_mass
            var total_force: float = clampf(spring_force + damp_force, -max_force, max_force)

            var force_vec: Vector3 = total_force * spring_direction
            state.apply_impulse(
                force_vec * sub_step,
                spring_midpoint
            )

            # Negate gravity, not exceeding the capability of a single leg
            var grav_force_vec: Vector3
            if true:
                grav_force_vec = -total_gravity * minf(mass * leg_gravity_power[leg.index], max_leg_mass)
                if debug_enable and debug_leg_gravity:
                    total_grav_vec += (
                          (grav_force_vec + (anti_gravity_point - state.center_of_mass)) * sub_step
                    )
            else:
                grav_force_vec = -total_gravity * shared_mass

            state.apply_impulse(
                grav_force_vec * sub_step,
                anti_gravity_point
            )

            var ground_state := PhysicsServer3D.body_get_direct_state(leg.ground_body)
            if ground_state:
                ground_state.apply_impulse(
                    -(force_vec + grav_force_vec) * sub_step,
                    leg.ground_point - ground_state.transform.origin
                )

        if iteration >= max_iterations:
            break

        # Update the body virtually
        state.transform.origin += state.linear_velocity * sub_step
        var angular_len: float = state.angular_velocity.length()
        if not is_zero_approx(angular_len):
            state.transform.basis = state.transform.basis.rotated(state.angular_velocity / angular_len, angular_len * sub_step)
            # NOTE: when changing rotation, need to tell physics server to update so inertia is accurate
            PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, state.transform)

    if debug_enable:
        if debug_leg_polygon:
            var polygon: PackedVector3Array
            polygon.resize(grounded_leg_count)
            for i in range(grounded_leg_count):
                polygon[i] = state.transform * Vector3(leg_polygon[i].x, grounded_leg_avg_displacement, leg_polygon[i].y)
            _debug_leg_polyline = DebugDraw.polyline(
                polygon,
                true,
                Color.MEDIUM_PURPLE,
                _debug_leg_polyline,
                0.05
            )
        if debug_leg_gravity:
            _debug_leg_gravity_vec = DebugDraw.vector(
                state.transform.origin,
                total_grav_vec * 0.1,
                Color.MEDIUM_SEA_GREEN,
                _debug_leg_gravity_vec,
                0.1
            )

    # Try to maintain original angular velocity (extra damping, basically)
    state.angular_velocity = state.angular_velocity.move_toward(old_angular, rotation_acceleration * leg_ratio * state.step)

    # Reset changes to the transform
    state.transform = old_transform
    PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, state.transform)


func _calculate_leg_gravity_power(state: PhysicsDirectBodyState3D) -> void:
    # NOTE: Parameterize the iteration count
    const MAX_ITERATIONS: int = 2
    # NOTE: parameterize the rate of rest (decay???)
    var decay_rate: float = pow(0.5, state.step)
    var dead_decay_rate: float = pow(0.1, state.step / 0.1) # roughly 10% after 0.1 seconds

    var count: int = leg_gravity_power.size()
    var points: PackedVector3Array
    points.resize(count)
    for leg in legs:
        if not leg.apply_ground_forces:
            points[leg.index] = Vector3.INF
            continue

        points[leg.index] = leg_update_data[leg.index * 3 + 2] - state.center_of_mass

    if grounded_leg_count < 2:
        for i in range(count):
            if points[i].is_finite():
                leg_gravity_power[i] = 1.0
            else:
                leg_gravity_power[i] = 0.0
        return

    var rots: PackedVector3Array
    rots.resize(count)
    rots.fill(Vector3.ZERO)
    var rot_normals: PackedVector3Array
    rot_normals.resize(count)
    rot_normals.fill(Vector3.ZERO)

    # NOTE: Used to calculate power share by assuming a leg is capable of lifting the entire body,
    #       although in practice this will have limitations.
    var anti_gravity: Vector3 = -state.total_gravity * state.step / state.inverse_mass

    var markiplier: float = minf(2.0 / float(grounded_leg_count), 1.0)
    var power_avg: float = 1.0 / float(grounded_leg_count)
    var it_step: float = 1.0 / float(MAX_ITERATIONS)
    for iteration in range(MAX_ITERATIONS):
        var new_power := PackedFloat64Array(leg_gravity_power)

        var rot_total: Vector3 = Vector3.ZERO
        for i in range(count):
            var point: Vector3 = points[i]
            if not point.is_finite():
                continue

            rot_normals[i] = state.inverse_inertia * point.cross(anti_gravity)
            rots[i] = rot_normals[i] * maxf(new_power[i], 0.001)

            rot_total += rots[i]

        # Scale method, each point moves its work to match what is needed, and is always slowly relaxing
        var power_total: float = 0.0
        for i in range(count):
            var work: float = new_power[i]
            var max_length: float = rot_normals[i].length()

            var new_work: float = work
            if not legs[i].apply_ground_forces:
                new_work *= dead_decay_rate
            elif not is_zero_approx(max_length):
                var grad: Vector3 = rots[i]
                var new_grad: Vector3 = grad - (rot_total * markiplier)
                var grad_dir: Vector3 = rot_normals[i] / max_length
                var dot_grad: float = new_grad.dot(grad_dir)

                if dot_grad < 0.0:
                    new_grad = Vector3.ZERO
                else:
                    new_grad = grad_dir * dot_grad

                new_work = new_grad.length() / max_length
                new_work *= pow(decay_rate, new_work / power_avg)

            new_power[i] = maxf(new_work, 0.0)
            power_total += new_power[i]

        if power_total > 0.0:
            for i in range(count):
                new_power[i] /= power_total

        power_total = 0.0
        for i in range(count):
            # NOTE: parameterize the rate of change
            leg_gravity_power[i] = move_toward(leg_gravity_power[i], new_power[i], 4.0 * state.step * it_step)
            power_total += leg_gravity_power[i]

        if power_total > 1.0:
            for i in range(count):
                leg_gravity_power[i] /= power_total

func _solve_rotation(state: PhysicsDirectBodyState3D) -> void:

    var can_do_yaw: bool = target_direction.is_finite()
    if can_do_yaw:
        for leg in legs:
            if (not leg.is_comfortable) and (not leg.is_stepping):
                can_do_yaw = false
                break

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
        if leg.apply_ground_forces:
            ground_points[i] = leg.ground_point
        elif leg.is_stepping:
            ground_points[i] = leg.global_transform * leg.step_target
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

    var roll: float = current_right.signed_angle_2(preferred_right, -preferred_forward)
    var pitch: float = current_forward.signed_angle_2(preferred_forward, preferred_right)

    var angular: Vector3 = Vector3(pitch, yaw, roll)
    angular.x = 0.0
    angular.z = 0.0

    # roughly 0.5 degrees
    if angular.length_squared() > 7.62e-5:
        has_desired_rotation = true

    var max_angular: Vector3 = angular / state.step
    var limited_angular: Vector3 = angular.sign() * max_angular.abs().minf(rotation_rate * (1.0 / rotation_overshoot))
    var target_angular: Vector3 = state.transform.basis * limited_angular

    state.angular_velocity = state.angular_velocity.move_toward(
            target_angular * rotation_overshoot,
            state.step * rotation_acceleration * grounded_leg_factor
    )

    if (not has_desired_rotation) and state.angular_velocity.length_squared() < 7.62e-5:
        # Low angular velocity, facing the target, clear target
        target_direction = Vector3.INF
