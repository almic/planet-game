@tool
class_name CrawlerCharacter extends CharacterController


@warning_ignore("unused_private_class_variable")
@export_tool_button('Rebuild Crawler', 'SphereMesh')
var _btn_rebuild_crawler = editor_rebuild_crawler

@warning_ignore("unused_private_class_variable")
@export_tool_button('Advance Skeleton', 'Skeleton3D')
var _btn_step_skeleton = editor_step_skeleton


@export var skeleton: Skeleton3D

@export var leg_ik: IKModifier

@export var physical_skeleton: PhysicalSkeleton

## Whole body mass of the crawler. This is used with 'Leg Mass Ratio' to
## disperse the mass between the main body and the individual leg segments.
@export_range(0.01, 100.0, 0.01, 'or_greater')
var total_mass: float = 30.0:
    set(value):
        total_mass = value
        _update_body_mass()

@export_custom(PROPERTY_HINT_NONE, '', PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var _single_leg_mass: float = 0.0


@export_group('Leg Mass')

## How many legs are equivalent to the mass of the central body. When greater
## than the total number of legs, more than 50% of the total mass will be
## concentrated in the main body.
@export_range(1.0, 16.0, 0.01, 'or_greater')
var body_leg_mass_ratio: float = 5.0:
    set(value):
        body_leg_mass_ratio = value
        _update_body_mass()

## Leg segment ratios. The first ratio determines how much of the total leg mass
## the first segment gets, the second determines how much of the remainder the
## second segment gets, and so on. The last segment will always get the full
## remainder of the mass, regardless of the value here.
@export var leg_segment_ratio: PackedFloat32Array:
    set(value):
        leg_segment_ratio = value
        _update_body_mass()

#region Movement Parameters
@export_group('Movement Parameters')

@export_range(0.01, 8.0, 0.01, 'or_greater')
var max_speed: float = 3.0

@export_range(0.0, 30.0, 0.1, 'or_greater', 'radians_as_degrees')
var max_pitch: float = deg_to_rad(12.0)

@export_range(0.0, 360.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rotation_acceleration: float = deg_to_rad(270.0)

## Maximum rotation speed when turning
@export_range(0.1, 180.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rotation_rate: float = deg_to_rad(180.0)

@export_range(0.0, 1.0, 0.01, 'or_greater')
var rotation_overshoot: float = 0.2
#endregion Movement Parameters

#region IK Parameters
@export_group('IK Parameters', 'ik')

## Number of iteration loops used by the IK solver to produce more accurate results.
@export_range(0, 10, 1, 'or_greater')
var ik_max_iterations: int = 4:
    set(value):
        ik_max_iterations = value
        _queue_update_ik_settings()

## Minimum number of iteration loops used by the IK solver even when it has reached the goal distance.
@export_range(0, 10, 1, 'or_greater')
var ik_min_iterations: int = 1:
    set(value):
        ik_min_iterations = value
        _queue_update_ik_settings()

## The target solve distance between the end bone and the target node.
## Iteration will only run while the distance is greater than this value.
@export_range(0.0, 1.0, 0.001, 'or_greater')
var ik_min_distance: float = 0.001:
    set(value):
        ik_min_distance = value
        _queue_update_ik_settings()

## The total angular change allowed per second. This is divided evenly between
## each iteration relative to the current `Engine.physics_ticks_per_second`,
## unlike the Godot implementation which applies it per-iteration and doesn't
## consider frame rate or physics TPS.
@export_range(0.01, 360.0, 0.01, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var ik_angular_delta_limit: float = deg_to_rad(180.0):
    set(value):
        ik_angular_delta_limit = value
        _queue_update_ik_settings()
#endregion IK Parameters

#region Leg Parameters
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
var body_leg_lift_ratio: float = 0.5

## How much effective acceleration legs can apply to the body. Should be just
## enough to be stable while being pushed and entering extreme inclines.
@export_range(0.01, 30.0, 0.01, 'or_greater')
var body_max_leg_force: float = 20.0

## The number of grounded legs necessary for jumping
@export_range(1, 8, 1, 'or_less')
var body_legs_needed_for_jump: int = 3
#endregion Leg Parameters

#region Debug
@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false

@export var debug_leg_polygon: bool = false
var _debug_leg_polyline: int = 0

@export var debug_leg_gravity: bool = false
var _debug_leg_gravity_vec: int = 0
#endregion Debug

var legs: Array[CrawlerLeg]

var target_position: Vector3 = Vector3.INF
var target_direction: Vector3 = Vector3.INF

## True when the body has either a desired foward direction or rotation
var has_desired_movement: bool:
    get():
        return has_desired_forward or has_desired_rotation

var has_desired_rotation: bool = false
## This vector is used to stabilize the forward direction
var stable_forward: Vector3
## When the real forward vector drifts the far from stable_forward, update
## stable_forward to the current forward vector, aligned to the up plane
const STABLE_FORWARD_DRIFT: float = cos(deg_to_rad(8.0))
var grounded_leg_count: int = 0
var grounded_leg_avg_displacement: float
var leg_update_data: PackedVector3Array
## When in motion, grounded legs should apply this transform to their target
## positions, enabling them to effectively propel the main body.
var leg_target_delta: Transform3D
var leg_polygon: PackedVector2Array
var leg_gravity_power: PackedFloat64Array

var leg_set_first: Array[CrawlerLeg]
var leg_set_second: Array[CrawlerLeg]

var _is_update_ik_queued: bool = false

func editor_rebuild_crawler() -> void:
    var dialog: Window
    if self != get_tree().edited_scene_root:
        dialog = AcceptDialog.new()
        dialog.dialog_text = (
            'You may only build crawlers within their scene file.\nTo build '
            + 'this crawler, open the scene:\n\n%s'
        ) % scene_file_path
    else:
        dialog = ConfirmationDialog.new()
        dialog.dialog_text = (
            'This will delete existing chain nodes and create new ones, adding '
            + 'them to this scene file.\nAre you sure?'
        )
        dialog.confirmed.connect(
            func():
                rebuild_crawler(false, true)
                EditorInterface.mark_scene_as_unsaved()
        )

    EditorInterface.popup_dialog_centered(dialog)

func editor_step_skeleton() -> void:
    if not Engine.is_editor_hint():
        return

    if not skeleton:
        push_warning('Skeleton not found!')
        return

    skeleton.advance(1.0 / float(Engine.physics_ticks_per_second), true)

## Clears and builds the crawler body.
## Enable editor mode to use popups for issues.
func rebuild_crawler(remove_unowned_nodes: bool = false, editor_mode: bool = false) -> void:
    if not physical_skeleton:
        push_error('Missing a physical skeleton. This is needed to build the bone bodies.')
        return

    _load_legs()

    # Clear IK settings, fully managed by chains
    leg_ik.set_setting_count(0)

    for leg in legs:
        if not leg.physical_bone_chain:
            continue

        if leg.index >= leg_ik.setting_list.size():
            leg_ik.set_setting_count(leg.index + 1)

        leg.apply_position()
        leg.setup_target()

        var success: bool = physical_skeleton.remove_chain(leg.physical_bone_chain, remove_unowned_nodes)

        if not success:
            if (not editor_mode) or remove_unowned_nodes:
                push_error(
                    (
                        'Failed to remove the chain for leg %s using resource named '
                        + '%s at %s. Errors should be above.'
                    ) % [
                        leg.name, leg.physical_bone_chain.resource_name, leg.physical_bone_chain.resource_path
                    ]
                )
                return

            # Scan for the "unowned" children
            var bad_chain := physical_skeleton.get_chain_node(leg.physical_bone_chain)
            if not bad_chain:
                # ?? what? ok i guess?
                pass
            else:
                var unowned_children: Array[Node]

                for child in bad_chain.find_children('*', '', true, false):
                    if child.has_meta(PhysicalSkeleton.META_OWNED):
                        continue
                    unowned_children.append(child)

                if unowned_children.size() == 0:
                    push_error(
                        (
                            'Failed to remove the chain for leg %s using resource named '
                            + '%s at %s. Could not find unowned nodes preventing removal. '
                            + 'Errors should be above.'
                        ) % [
                            leg.name, leg.physical_bone_chain.resource_name, leg.physical_bone_chain.resource_path
                        ]
                    )
                    return

                var dialog := ConfirmationDialog.new()
                dialog.dialog_text = (
                    'Unable to remove the chain for leg %s using the resource '
                    + 'named %s at %s.\nFound nodes NOT created by the chain, '
                    + 'likely preventing removal.\nWould you like to retry and '
                    + 'DELETE THESE NODES:\n%s'
                ) % [
                    leg.name,
                    leg.physical_bone_chain.resource_name,
                    leg.physical_bone_chain.resource_path,
                    '\n'.join(unowned_children.map(
                        func (node): return '- %s at %s' % [node.name, get_nice_path(node)]
                    ))
                ]

                EditorInterface.popup_dialog_centered(dialog)
                var confirmed: bool = bool(await Signals.any([dialog.canceled, dialog.confirmed]))
                if not confirmed:
                    return

                success = physical_skeleton.remove_chain(leg.physical_bone_chain, true)
                if not success:
                    EditorInterface.get_editor_toaster().push_toast(
                        'Failed to remove chain for leg %s, console should contain errors.' % leg.name,
                        EditorToaster.SEVERITY_ERROR
                    )
                    return

        var chain: PhysicalBoneChain3D = physical_skeleton.build_chain(
                leg.physical_bone_chain, leg.build_custom_joint
        )

        if not chain:
            push_error(
                (
                    'Failed to build the chain for leg %s using resource named '
                    + '%s at %s. Errors should be above.'
                ) % [
                    leg.name, leg.physical_bone_chain.resource_name, leg.physical_bone_chain.resource_path
                ]
            )
            return

        if chain.is_ik_enabled:
            chain.set_ik(leg_ik, leg.index)
    # NOTE: building chains defers the setup for bone part maps on physical
    #       skeleton, so we must defer the mass update
    _update_body_mass.call_deferred()


func _ready() -> void:
    super._ready()

    stable_forward = -global_basis.z
    physical_skeleton.skeleton = skeleton
    physical_skeleton.joint_force_exceeded.connect(on_joint_force_exceeded)

    _load_legs(true)
    _update_body_mass()
    _queue_update_ik_settings()

    if Engine.is_editor_hint():
        # Allow physical skeleton to match bone meshes to IK results
        leg_ik.modification_processed.connect(physical_skeleton.on_pose_finalized)

    var count: int = legs.size()
    leg_update_data.resize(count * 3)
    leg_gravity_power.resize(count)
    leg_gravity_power.fill(0.0)

    # Collect leg rigid bodies to ignore for shape casts
    var leg_cast_exclude_list: Array[RID] = [get_rid()]
    for body in find_children('', 'CollisionObject3D'):
        if body is CollisionObject3D:
            leg_cast_exclude_list.append(body.get_rid())

    _calculate_leg_sets()

    # Initialize legs
    for leg in legs:
        if leg in leg_set_first:
            leg.setup(leg_cast_exclude_list, leg_set_first)
        else:
            leg.setup(leg_cast_exclude_list, leg_set_second)

    if Engine.is_editor_hint():
        return

    leg_ik.active = true
    physical_skeleton.active = true
    physical_skeleton.modification_processed.connect(_update_legs)
    leg_ik.modification_processed.connect(physical_skeleton.on_pose_finalized)

func get_nice_path(to: Node = null) -> NodePath:
    if not is_inside_tree():
        return NodePath("")

    if not to:
        to = self

    if not to.is_inside_tree():
        print_stack()
        push_error(
            (
                'get_nice_path() called with node not in the scene tree: "%s" %s'
            ) % [to.name, to]
        )
        return NodePath("")

    var root_node: Node = get_tree().edited_scene_root
    if not root_node:
        root_node = get_tree().current_scene
    if not root_node:
        root_node = get_viewport()
    if not root_node:
        root_node = get_window()
    if root_node:
        return root_node.get_path_to(to)
    return to.get_path()

func _load_legs(is_initialization: bool = false) -> void:
    for old_leg in legs:
        old_leg.index = -1
        old_leg.body = null

    # Load legs from children
    legs.assign(find_children('', 'CrawlerLeg'))

    var count: int = legs.size()
    for i in range(count):
        var leg: CrawlerLeg = legs[i]
        leg.body = self
        leg.index = i

        if not is_initialization:
            continue

        if leg.physical_bone_chain:
            physical_skeleton.prepare_custom_joints(leg.physical_bone_chain, leg.prepare_custom_joint)
        else:
            continue
            push_error(
                (
                    'CrawlerCharacter at %s has a CrawlerLeg at %s which is '
                    + 'missing a physical bone chain resource. Please give it '
                    + 'a resource or delete the leg node.'
                ) % [get_nice_path(), get_nice_path(leg)]
            )

        if Engine.is_editor_hint():
            continue

func _queue_update_ik_settings() -> void:
    if _is_update_ik_queued:
        return
    _is_update_ik_queued = true
    _update_ik_settings.call_deferred()

func _update_ik_settings() -> void:
    _is_update_ik_queued = false
    if not leg_ik:
        return

    leg_ik.iterations = ik_max_iterations
    leg_ik.min_iterations = ik_min_iterations
    leg_ik.min_distance = ik_min_distance
    leg_ik.angular_delta_limit = ik_angular_delta_limit

func damage(source: Object, amount: float, hit_point: Vector3) -> void:
    print('Took %f damage from %s at position %s' % [amount, source.name, str(hit_point)])

func on_joint_force_exceeded(
        joint: Joint3D,
        force: float,
        _max_force: float,
        _part: PhysicalBonePart3D,
        _chain: PhysicalBoneChain3D,
) -> void:
    print('%d : %s: %.2f' % [Engine.get_physics_frames(), get_nice_path(joint), force])

func _update_body_mass() -> void:
    """
    My math homework for these equations:

    TotalMass = B + nL
    B = Ratio * L
    L = B / Ratio

    TotalMass = B + n(B / Ratio)
    TotalMass = B * (1 + (n / Ratio))
    B = TotalMass / (1 + (n / Ratio))

    TotalMass = (Ratio * L) + nL
    TotalMass = L * (Ratio + n)
    L = TotalMass / (Ratio + n)
    """
    var leg_count: int = legs.size()
    if leg_count == 0:
        return # Not ready yet
    var body_mass: float = total_mass / (1 + (leg_count / body_leg_mass_ratio))
    var leg_mass: float = total_mass / (leg_count + body_leg_mass_ratio)

    mass = body_mass
    _single_leg_mass = leg_mass

    # Now for the hard part, distribute leg_mass to bone bodies in physical chains
    var bone_part_map: Dictionary[int, PhysicalBonePart3D] = physical_skeleton.get_bone_part_map()
    for chain in physical_skeleton.chain_list:
        var remaining_mass: float = leg_mass
        var mass_ratio: float = 1.0
        for index in range(chain.part_count):
            var bone_for_body: int = chain.bone_list[index]
            var body: PhysicalBonePart3D = bone_part_map.get(bone_for_body)
            if not body:
                push_error("Bone %s does not have an associated RigidBody3D! Fix!!" % skeleton.get_bone_name(bone_for_body))
                return

            # Give last body the remaining mass
            if index == chain.part_count - 1:
                body.mass = remaining_mass
                break

            if index < leg_segment_ratio.size():
                mass_ratio = leg_segment_ratio[index]

            body.mass = remaining_mass * mass_ratio
            remaining_mass -= body.mass

func _handle_input() -> void:

    var body_center: Vector3 = position + PhysicsServer3D.body_get_param(get_rid(), PhysicsServer3D.BODY_PARAM_CENTER_OF_MASS)
    var to_target: Vector3 = target_position - body_center

    if target_position.is_finite() and to_target.length_squared() > 4.0:
        var to_target_dir: Vector3 = to_target.normalized()
        target_direction = to_target_dir
        desired_direction = to_target_dir
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
    ground_velocity = Vector3.ZERO

    grounded_leg_count = 0

    for leg in legs:
        leg.on_physics_update()
        # TODO: handle leg being broken somehow
        if leg.is_grounded:
            grounded_leg_count += 1
            ground_normal += leg.ground_normal
            ground_position += leg.ground_position
            ground_velocity += leg.ground_contact_velocity

    if grounded_leg_count > 0:
        is_on_floor = true
        ground_position /= grounded_leg_count

        if ground_normal.is_zero_approx():
            ground_normal = state.transform.basis.y
        else:
            ground_normal = ground_normal.normalized()

        if grounded_leg_count >= body_legs_needed_for_jump:
            has_landed_on_ground_for_jump = true
    else:
        ground_position = Vector3.INF

func _calculate_ground_vectors(state: PhysicsDirectBodyState3D) -> void:

    ground_direction = Vector3.ZERO
    ground_rel_con_velocity = Vector3.ZERO
    ground_friction = Vector3.ZERO

    if not is_on_floor:
        return

    ground_rel_con_velocity = state.linear_velocity - ground_velocity
    ground_velocity = ground_rel_con_velocity.slide(state.transform.basis.y).slide(ground_normal)

    for leg in legs:
        ground_friction += leg.ground_friction

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO

func _custom_pre_movement_forces(state: PhysicsDirectBodyState3D) -> void:
    _solve_rotation(state)

func _post_integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    # This kicks off several callbacks:
    #   1. Matches skeleton pose to physical joints and updates chain forces
    #   2. Calls _update_legs(), which
    #   3. IterateIK moves joints towards targets
    #   4. PhysicalSkeleton calculates joint motor velocities for the next physics step
    skeleton.advance(state.step, true)

func _update_legs() -> void:
    # NOTE: Disable any IK here, this is between the physical skeleton and ik
    var any_legs_just_broken: bool = false
    for chain in physical_skeleton.chain_list:
        if not chain.is_ik_enabled:
            continue

        # Disable IK behavior on the chain and update legs
        if chain.is_any_motor_broken:
            chain.is_ik_enabled = false # mark disabled to skip in the future
            # NOTE: setting node path to empty effectively disables that ik setting
            leg_ik.setting_list[chain.ik_setting].target_node = NodePath("")
            legs[chain.ik_setting].is_broken = true
            any_legs_just_broken = true

    if any_legs_just_broken:
        _update_leg_sets()

    for leg in legs:
        leg.update()

func _solve_rotation(state: PhysicsDirectBodyState3D) -> void:

    var has_target_direction: bool = target_direction.is_finite()
    var can_do_yaw: bool = has_target_direction
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

    var ground_points: PackedVector3Array
    var first_ground_normal: Vector3 = Vector3.INF
    var desired_angular_velocity: Vector3 = Vector3.ZERO
    var valid_point_count: int = leg_count
    ground_points.resize(leg_count)

    for i in range(leg_count):
        var leg: CrawlerLeg = legs[i]
        if leg.is_grounded:
            if is_inf(first_ground_normal.x):
                first_ground_normal = leg.ground_normal
            ground_points[i] = to_local(leg.ground_position)
            # Given a point and a linear velocity, angular velocity is: w = (p x v) / p^2
            var dv: Vector3 = leg.ground_position - (state.transform.origin + state.center_of_mass)
            desired_angular_velocity += dv.cross(leg.contact_velocity) / dv.length_squared()
        elif leg.is_stepping:
            ground_points[i] = to_local(leg.step_target_current)
        else:
            ground_points[i] = Vector3.INF
            valid_point_count -= 1

    if grounded_leg_count > 1:
        desired_angular_velocity /= grounded_leg_count

    var preferred_up: Vector3
    if valid_point_count == 1:
        preferred_up = first_ground_normal
    else:
        preferred_up = _calculate_preferred_up(valid_point_count, ground_points)
        preferred_up = state.transform.basis * preferred_up

    # Fix stable_forward
    var target_forward: Vector3
    if has_target_direction:
        target_forward = target_direction
    else:
        target_forward = -state.transform.basis.z

    if target_forward.dot(stable_forward) > STABLE_FORWARD_DRIFT:
        stable_forward = target_forward
    elif not desired_angular_velocity.is_zero_approx():
        # NOTE: rotate with desired angular velocity, maintains forward relative to legs
        stable_forward = stable_forward.rotated(-desired_angular_velocity.normalized(), desired_angular_velocity.length() * state.step)

    # Calculate preferred forward and right from current orientation
    var preferred_right: Vector3 = stable_forward.cross(preferred_up).normalized()
    var preferred_forward: Vector3 = preferred_up.cross(preferred_right).normalized()

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
    else:
        yaw = current_forward.signed_angle_2(preferred_forward, preferred_up)

    var roll: float = current_right.signed_angle_2(preferred_right, -preferred_forward)
    var pitch: float = current_forward.signed_angle_2(preferred_forward, preferred_right)

    var angular: Vector3 = Vector3(pitch, yaw, roll)

    # roughly 0.5 degrees
    const LOW_ANGLE: float = 7.62e-5
    if has_target_direction or angular.length_squared() > LOW_ANGLE:
        has_desired_rotation = true

    # Relative angular to rotate into preferred orientation
    var max_angular: Vector3 = (angular * (1.0 + rotation_overshoot)) / state.step
    var limited_angular: Vector3 = angular.sign() * max_angular.abs().minf(rotation_rate)
    var relative_angular: Vector3 = state.transform.basis * limited_angular

    var angular_delta: Vector3 = desired_angular_velocity + relative_angular - state.angular_velocity

    state.angular_velocity += (angular_delta * grounded_leg_factor).limit_length(rotation_acceleration) * state.step

    if relative_angular.length_squared() < LOW_ANGLE and angular_delta.length_squared() < LOW_ANGLE:
        # Low angular velocity, facing the target, clear target
        target_direction = Vector3.INF

## Calculates a preferred up from ground points, creating a triangle for each
## set of three contact points. If only two points are available, up is calculated
## as the direction closest to (0, 1, 0) that is perpendicular to the segment.
func _calculate_preferred_up(valid_points: int, ground_points: PackedVector3Array) -> Vector3:
    if valid_points < 2:
        return Vector3.UP

    var current_point: Vector3

    if valid_points == 2:
        var first_point: Vector3 = Vector3.INF
        var second_point: Vector3 = Vector3.INF
        for i in range(ground_points.size()):
            current_point = ground_points[i]
            if is_inf(current_point.x):
                continue

            if is_inf(first_point.x):
                first_point = current_point
                continue

            second_point = current_point
            break

        var forward: Vector3 = second_point - first_point
        var right: Vector3 = Vector3.UP.cross(forward)
        var up: Vector3 = forward.cross(right)
        if up.is_zero_approx():
            return Vector3.UP

        return up.normalized()

    var preferred_up: Vector3 = Vector3.ZERO
    var initial_point: Vector3 = Vector3.INF
    var current_side: Vector3
    var last_side: Vector3 = Vector3.INF
    for i in range(ground_points.size()):
        current_point = ground_points[i]
        if is_inf(current_point.x):
            continue

        if is_inf(initial_point.x):
            initial_point = current_point
            continue

        current_side = current_point - initial_point

        if not is_inf(last_side.x):
            var plane_dir: Vector3 = current_side.cross(last_side)
            if not plane_dir.is_zero_approx():
                plane_dir = plane_dir.normalized()
                if plane_dir.dot(Vector3.UP) < 0.0:
                    plane_dir = -plane_dir
                preferred_up += plane_dir

        last_side = current_side

    if preferred_up.is_zero_approx():
        return Vector3.UP

    return preferred_up.normalized()

func _update_leg_sets() -> void:
    _calculate_leg_sets()
    for leg in legs:
        if leg in leg_set_first:
            leg.sync_paired = leg_set_first
        else:
            # NOTE: broken legs will default to second set, but won't actually
            #       exist in the second set
            leg.sync_paired = leg_set_second

func _calculate_leg_sets() -> void:
    leg_set_first.clear()
    leg_set_second.clear()

    var good_leg_set: Array[CrawlerLeg] = []
    var left_side: int = 0
    var right_side: int = 0
    for leg in legs:
        if leg.is_broken:
            continue

        good_leg_set.append(leg)

        if leg.is_left:
            left_side += 1
        else:
            right_side += 1

    var good_leg_count: int = good_leg_set.size()
    var missing_count: int = legs.size() - good_leg_count

    if missing_count <= 1:
        # Missing up to 1 leg, use AB, BA pairing
        for leg in good_leg_set:
            var leg_pair: int = leg.index % 4
            if leg_pair == 0 or leg_pair == 3:
                leg_set_first.append(leg)
            else:
                leg_set_second.append(leg)
        return

    if missing_count >= 4 or left_side == 0 or right_side == 0:
        # All legs on one side, or fewer than three, simple alternate rule
        for index in range(good_leg_count):
            if index % 2 == 0:
                leg_set_first.append(good_leg_set[index])
            else:
                leg_set_second.append(good_leg_set[index])
        return

    if missing_count == 2:
        # It may be possible to create diagonal pairs, but can fail
        # Counting most likely layouts, this is most likely to fail 1/3 times
        var current_leg: CrawlerLeg = good_leg_set[0]
        leg_set_first.append(current_leg)

        for index in range(1, good_leg_count):
            var leg: CrawlerLeg = good_leg_set[index]
            if leg.is_left != current_leg.is_left:
                leg_set_first.append(leg)
                break

        # This should succeed, but just in case...
        if leg_set_first.size() == 2:
            # Second diagonal
            for leg in good_leg_set:
                if leg_set_second.size() == 0:
                    if leg not in leg_set_first:
                        current_leg = leg
                        leg_set_second.append(leg)
                    continue

                if leg in leg_set_first:
                    continue

                # Must be opposite side, not on the same row
                @warning_ignore("integer_division")
                if (
                            current_leg.is_left != leg.is_left
                        and int(current_leg.index / 2) != int(leg.index / 2)
                ):
                    leg_set_second.append(leg)
                break

            # Test for failure
            if leg_set_second.size() == 2:
                return

            leg_set_first.clear()
            leg_set_second.clear()

    # At least 3 legs and at least 1 per side. Special algorithm.
    # Start with the first leg on the "least-legged" side, then pair with first:
    #   1. If it is a middle leg, select the leg above
    #   2. The leg on the same row
    #   3. The first leg ahead of it
    #   4. The first leg behind it
    # The remaining legs become the second pair

    # Least-legged side leg
    var least_legged_is_left: bool = left_side < right_side
    var least_leg: CrawlerLeg
    var least_leg_good_index: int = 0
    for leg in good_leg_set:
        if leg.is_left == least_legged_is_left:
            least_leg = leg
            break
        least_leg_good_index += 1

    @warning_ignore("integer_division")
    var least_leg_row: int = int(least_leg.index / 2)

    leg_set_first.append(least_leg)

    if least_leg.index >= 2 and least_leg.index < legs.size() - 2:
        for index in range(least_leg_good_index - 1, -1, -1):
            var leg: CrawlerLeg = good_leg_set[index]

            @warning_ignore("integer_division")
            if int(leg.index / 2) != least_leg_row:
                leg_set_first.append(leg)
                break
    else:
        var row_candidate_index: int = least_leg_good_index
        var candidate_index: int = least_leg.index
        if least_leg.is_left:
            row_candidate_index += 1
            candidate_index += 1
        else:
            row_candidate_index -= 1
            candidate_index -= 1

        # Same row
        if (
                    row_candidate_index > 0
                and row_candidate_index < good_leg_count
                and good_leg_set[row_candidate_index].index == candidate_index
        ):
            leg_set_first.append(good_leg_set[row_candidate_index])
        # First leg ahead
        elif least_leg_good_index - 1 >= 0:
            leg_set_first.append(good_leg_set[least_leg_good_index - 1])
        # First leg behind
        else:
            leg_set_first.append(good_leg_set[least_leg_good_index + 1])

    # Add others to second set
    for leg in good_leg_set:
        if leg not in leg_set_first:
            leg_set_second.append(leg)
