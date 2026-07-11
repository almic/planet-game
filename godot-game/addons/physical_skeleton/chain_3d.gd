@tool
class_name PhysicalBoneChain3D extends Node3D


@export_custom(
    PROPERTY_HINT_NONE,
    '',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var resource: PhysicalBoneChainResource

@export_custom(
    PROPERTY_HINT_NODE_TYPE,
    'IKModifier',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var ik_node: IKModifier

@export_custom(
    PROPERTY_HINT_NONE,
    '',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var ik_setting: int = -1


## Set by PhysicalSkeleton when creating new chains, to skip the ready method
var _skip_ready: bool = false

var is_valid: bool = false
var is_ik_enabled: bool = false

var skeleton: Skeleton3D

## This chain is using power for motors
var is_using_power: bool = false
## This chain has at least one broken motor
var is_any_motor_broken: bool = false

var bone_list: PackedInt32Array
var part_list: Array[PhysicalBonePart3D]
var part_count: int

var _part_initial_angular: PackedVector3Array
var _part_initial_basis: Array[Basis]

var _has_cached_main_body: bool = false
var _cached_main_body_angular: Vector3 = Vector3.ZERO
var _cached_main_body_transform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
    if _skip_ready:
        return
    reload_chain()

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

## Returns a mapping of each part's related bone index to the array of joints.
## The provided arrays are read-only, and must be duplicated before modifying them
func get_bone_joint_map() -> Dictionary[int, Array]:
    var bone_joint_map: Dictionary[int, Array]

    for i in range(part_count):
        bone_joint_map.set(bone_list[i], part_list[i].get_joint_list())

    return bone_joint_map

func get_bone_part_map() -> Dictionary[int, PhysicalBonePart3D]:
    var result: Dictionary[int, PhysicalBonePart3D]
    for i in range(part_count):
        result.set(bone_list[i], part_list[i])

    return result

func set_joint_force_exceeded_signal(sig: Signal) -> void:
    for part in part_list:
        part.joint_force_exceeded_emit = sig.emit.bind(self)

func build_chain(main_body: RigidBody3D, custom_joint_builder: Callable) -> bool:
    if not skeleton:
        # TODO: error
        push_error('missing skeleton')
        return false

    var build_bone_list: PackedInt32Array = resource.get_bone_list(skeleton)

    var parent_body: RigidBody3D = main_body
    for index in range(resource.part_list.size()):
        var part := PhysicalBonePart3D.new()
        part.set_meta(PhysicalSkeleton.META_OWNED, true)
        part.set_meta(&'_custom_type_script', ResourceUID.id_to_text(ResourceLoader.get_resource_uid((part.get_script() as Script).resource_path)))
        part.set_meta(&'_edit_lock_', true)
        part.resource = resource.part_list[index]
        part.name = part.resource.resource_name
        part.part_index = index
        part.transform = skeleton.get_bone_global_pose(build_bone_list[index]).orthonormalized()
        part.scale = Vector3.ONE # BUG: orthonormalization doesn't fix scale??

        part._skip_ready = true
        add_child(part, true)
        part.owner = owner

        var success: bool = part.build_part(
                self, main_body, parent_body, custom_joint_builder
        )

        if not success:
            push_error(
                (
                    'PhysicalBoneChain3D "%s" failed to build part "%s". Errors '
                    + 'should be above.'
                ) % [name, part.name]
            )
            return false

        parent_body = part

    reload_chain()

    return true

func prepare_custom_joints(custom_joint_callable: Callable) -> bool:
    for part in part_list:
        if not part.is_valid:
            push_error(
                (
                    'PhysicalBoneChain3D at %s has an invalid part at %s. There should be errors above.'
                ) % [get_nice_path(), part.get_nice_path()]
            )
            return false

        if not part.resource.custom_enabled:
            continue

        if not part.prepare_custom_joints(custom_joint_callable):
            return false

    return true

var last_end_pos: Vector3 = Vector3.INF
func update() -> void:
    var power_active: bool = true
    is_using_power = false

    for index in range(part_count):
        var part: PhysicalBonePart3D = part_list[index]
        part.is_powered = power_active

        part.update(skeleton, bone_list[index])

        if (not is_using_power) and part.is_powered and part.is_using_power:
            is_using_power = true

        if part.is_power_interrupted:
            power_active = false

        if (not is_any_motor_broken) and part.is_motor_broken:
            is_any_motor_broken = true

    # TODO:
    # Revised: After updating bone positions, end bone is perfectly in place
    #          and this probably isn't needed now! (June 27)
    # Original:
    #     TODO: I think this is still a good idea (June 13)
    #     IDEA: Teleport IK end bone to real location? Maybe this will help IK

func on_pose_finalized() -> void:
    for index in range(part_count):
        var part := part_list[index]
        if not part.is_valid:
            continue
        part.on_pose_finalized(skeleton, bone_list[index])

## Activates all rigid body parts of this chain
func activate(initial_state: PhysicsDirectBodyState3D) -> void:
    for i in range(part_count):
        var part: PhysicalBonePart3D = part_list[i]
        var bone: int = bone_list[i]

        # Teleport to bone
        part.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
        part.force_update_transform()

        # Copy state velocity
        var local_position: Vector3 = (part.global_position + part._cached_com) - initial_state.transform.origin
        part.linear_velocity = initial_state.get_velocity_at_local_position(local_position)
        part.angular_velocity = initial_state.angular_velocity

        part.activate()

## Disables all rigid body parts of this chain
func deactivate() -> void:
    for part in part_list:
        part.deactivate()

func set_ik(ik_modifier: IKModifier, setting_index: int) -> void:
    ik_node = ik_modifier
    ik_setting = setting_index

    on_ik_setting_changed()

    for part in part_list:
        on_part_ik_changed('', part.part_index)

func on_ik_setting_changed() -> void:
    var setting: IKModifier.ChainResource = ik_node.setting_list[ik_setting]
    setting.root_bone = resource.root_bone
    setting.end_bone = resource.end_bone
    setting.rest_correction = resource.rest_correction_rate

func on_part_ik_changed(setting_name: StringName, part_index: int) -> void:
    # TODO: only run when IK settings change
    var res: PhysicalBonePartResource = part_list[part_index].resource
    var chain_setting: IKModifier.ChainResource = ik_node.setting_list[ik_setting]
    if part_index >= chain_setting.joint_list.size():
        chain_setting.set_joint_count(part_index + 1)

    var joint_setting: IKModifier.JointResource = chain_setting.joint_list[part_index]
    joint_setting.rotation_axis = res.rotation_axis
    joint_setting.limitation_angle = res.limitation.angle
    joint_setting.limitation_rotation_offset = res.limitation.rotation_offset

func setup_velocity() -> void:
    _part_initial_angular.resize(part_count)
    _part_initial_basis.resize(part_count)

    for index in range(part_count):
        var part: PhysicalBonePart3D = part_list[index]
        part.setup_motor_velocity(skeleton, bone_list[index])

        var part_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.get_rid())
        _part_initial_angular[index] = part_state.angular_velocity
        _part_initial_basis[index] = part_state.transform.basis

func clean_part_state() -> void:
    for index in range(part_count):
        var part: PhysicalBonePart3D = part_list[index]
        var part_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.get_rid())

        part_state.angular_velocity = _part_initial_angular[index]

        var xform: Transform3D = part_state.transform
        xform.basis = _part_initial_basis[index]
        part_state.transform = xform

## Processes parts on the chain, accepting a main-body angular velocity and
## returning the estimated new velocity of the main-body.
func solve_velocity(
        main_body_state: PhysicsDirectBodyState3D,
        initial_main_angular_velocity: Vector3,
        initial_main_transform: Transform3D,
        delta: float,
        is_backwards: bool,
        do_state_update: bool,
) -> bool:

    # Set main body to our cached output
    if _has_cached_main_body:
        _has_cached_main_body = false
        main_body_state.angular_velocity = _cached_main_body_angular
        main_body_state.transform = _cached_main_body_transform
    else:
        main_body_state.angular_velocity = initial_main_angular_velocity
        main_body_state.transform = initial_main_transform

    if ik_setting == 0:
        breakpoint

    var index: int
    var step: int

    if is_backwards:
        index = part_count
        step = -1
    else:
        index = -1
        step = 1

    var count: int = part_count
    var had_impulse: bool = false
    while count > 0:
        count -= 1
        index += step

        var part: PhysicalBonePart3D = part_list[index]

        # The rest will be unpowered when iterating forward, so break early
        if not part.is_powered:
            if step > 0:
                break
            continue

        # The motor itself may be effectively destroyed, so no need to solve
        if part.is_motor_broken:
            continue

        _update_part_iteration(part, delta)

        var applied_impulse: bool = part.solve_motor_velocity(delta)
        had_impulse = had_impulse || applied_impulse

        continue
        print(
            (
                'Part %d:\n'
                + '  vel: %+.2f\n'
                + '  des: %+.2f\n'
                + '  trq:  %.2f'
            ) % [
                index,
                rad_to_deg(part.actual_joint_velocity),
                rad_to_deg(part.desired_motor_velocity),
                part.desired_motor_torque
            ]
        )

    if not do_state_update:
        return had_impulse

    # Reset parts and main body state
    clean_part_state()
    main_body_state.angular_velocity = initial_main_angular_velocity
    main_body_state.transform = initial_main_transform

    # Apply motors to angular velocity and rotations, in reverse to match the
    # joint priorities
    index = part_count
    var vel_results: PackedVector3Array
    while index > 0:
        index -= 1
        var part: PhysicalBonePart3D = part_list[index]

        var part_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.get_rid())
        var parent_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.bone_joint_data.parent)
        _calculate_part_velocity(part, delta, vel_results)

        parent_state.angular_velocity = vel_results[0]
        part_state.angular_velocity = vel_results[1]

    index = part_count
    while index > 0:
        index -= 1

        # NOTE: Assume perfectly rigid constraints, only rotate on the allowed
        # axis and apply the full rotation limits. This prevents joint motors
        # from acting like their constraints.
        var part: PhysicalBonePart3D = part_list[index]
        var joint_axis: Vector3 = part.bone_rotation_axis_vector

        var rid: RID = part.get_rid()
        var body_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(rid)
        var parent_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.bone_joint_data.parent)

        var xform: Transform3D = body_state.transform

        # Rotate on joint axis
        var joint_velocity: float = joint_axis.dot(body_state.angular_velocity)
        if absf(joint_velocity) > 1e-6:
            xform.basis = xform.basis.rotated(joint_axis, joint_velocity * delta)
            had_impulse = true

        # This updates the inverse inertia, which is needed for the constraint
        body_state.transform = xform

        # Rotation of joint
        var joint_to_parent: Quaternion = part.bone_joint_data.xform_rel_parent.basis.get_rotation_quaternion()
        var joint_to_body: Quaternion = part.bone_joint_data.xform_rel_body.basis.get_rotation_quaternion()
        var joint_parent: Quaternion = parent_state.transform.basis.get_rotation_quaternion()
        var joint_body: Quaternion = body_state.transform.basis.get_rotation_quaternion()
        var joint_q: Quaternion = (joint_to_body * joint_body) * (joint_to_parent * joint_parent).inverse()

        # Constrain rotation
        var q_swing: Quaternion
        var q_twist: Quaternion
        var q_s: float = sqrt((joint_q.w * joint_q.w) + (joint_q.x * joint_q.x))
        if q_s != 0.0:
            q_twist = Quaternion(joint_q.x / q_s, 0, 0, joint_q.w / q_s)
            q_swing = Quaternion(
                    0,
                    (joint_q.w * joint_q.y - joint_q.x * joint_q.z) / q_s,
                    (joint_q.w * joint_q.z + joint_q.x * joint_q.y) / q_s,
                    q_s
            )
        else:
            q_swing = joint_q

        var negate_swing: bool = q_swing.w < 0.0
        var negate_twist: bool = q_twist.w < 0.0
        if negate_swing:
            q_swing = -q_swing
        if negate_twist:
            q_twist = -q_twist

        if part.bone_rotation_axis == 0:
            # X, twist
            pass
        elif part.bone_rotation_axis == 2:
            # Z, swing
            pass
        else:
            # Y, swing
            pass

        # Flip signs back
        if negate_swing:
            q_swing = -q_swing
        if negate_twist:
            q_twist = -q_twist

        # Constrain to angle limitation
        var parent_tensor: Basis = parent_state.inverse_inertia_tensor
        var body_tensor: Basis = body_state.inverse_inertia_tensor
        var effective_mass: Basis
        for k in range(3):
            effective_mass[k] = body_tensor[k] + parent_tensor[k]

        var det: float = effective_mass.determinant()
        if det == 0.0:
            # Some axis must be locked, so identity any missing axis
            for k in range(3):
                if effective_mass[k][k] == 0.0:
                    effective_mass[k] = Vector3()
                    effective_mass[k][k] = 1.0
            det = effective_mass.determinant()

            # Cannot proceed, though this should probably never happen in-game, it
            # could happen in development in special cases. Either way, should still
            # check because it would be a div-by-zero
            if det == 0.0:
                continue

        effective_mass = effective_mass.inverse()

        var constraint_q_inv: Quaternion = ((q_twist * q_swing) * joint_to_parent).inverse() * joint_to_body
        var diff: Quaternion = joint_parent.inverse() * (constraint_q_inv * joint_body)

        if diff.w < 0.0:
            diff = -diff

        var error: Vector3 = 2.0 * Vector3(diff.x, diff.y, diff.z)
        if error == Vector3.ZERO:
            continue

        var lambda: Vector3 = -1.0 * (effective_mass * error)

        # Only correct the joint axis rotation
        var parent_delta: Vector3 = parent_state.inverse_inertia_tensor * lambda
        var delta_len: float = joint_axis.dot(parent_delta)
        if absf(delta_len) > 1e-6:
            xform = parent_state.transform
            xform.basis = xform.basis.rotated(joint_axis, -delta_len)
            parent_state.transform = xform
            had_impulse = true

        var body_delta: Vector3 = body_state.inverse_inertia_tensor * lambda
        delta_len = joint_axis.dot(body_delta)
        if absf(delta_len) > 1e-6:
            xform = body_state.transform
            xform.basis = xform.basis.rotated(joint_axis, delta_len)
            body_state.transform = xform
            had_impulse = true

    _cached_main_body_angular = main_body_state.angular_velocity
    _cached_main_body_transform = main_body_state.transform
    _has_cached_main_body = true

    return had_impulse

func _update_part_iteration(part: PhysicalBonePart3D, delta: float) -> void:
    var part_index: int = part.part_index
    var part_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.get_rid())
    var joint_velocity: Vector3

    var vel_results: PackedVector3Array
    if part_index - 1 >= 0:
        # Estimated parent body angular velocity
        _calculate_part_velocity(part_list[part_index - 1], delta, vel_results)
        joint_velocity = vel_results[1]
    else:
        var parent_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.bone_joint_data.parent)
        joint_velocity = parent_state.angular_velocity

    if part_index + 1 < part_list.size():
        # Estimated part body angular velocity
        _calculate_part_velocity(part_list[part_index + 1], delta, vel_results)
        joint_velocity -= vel_results[0]
    else:
        joint_velocity -= part_state.angular_velocity

    var joint_axis: Vector3 = part.bone_rotation_axis_vector
    var joint_axis_velocity: float = joint_axis.dot(joint_velocity)

    part.joint_velocity = joint_axis_velocity

    var rot: Quaternion = (_part_initial_basis[part_index].inverse() * part_state.transform.basis).get_rotation_quaternion()
    rot = Quaternion(rot * joint_axis, joint_axis) * rot
    var angle: float = rot.get_angle()
    if rot.get_axis().dot(joint_axis) < 0.0:
        angle = -angle

    part.rotation_error = angle

func _calculate_part_velocity(
        part: PhysicalBonePart3D,
        delta: float,
        results: PackedVector3Array,
) -> void:
    var part_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.get_rid())
    var parent_state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(part.bone_joint_data.parent)

    results.resize(2)
    results[0] = parent_state.angular_velocity
    results[1] = part_state.angular_velocity

    var torque: float = part.desired_motor_torque * delta
    if torque < 1e-6:
        return

    var joint_axis: Vector3 = part.bone_rotation_axis_vector

    var part_inv_inertia: Vector3 = part_state.inverse_inertia_tensor * joint_axis
    var parent_inv_inertia: Vector3 = parent_state.inverse_inertia_tensor * joint_axis
    var effective_mass: float = 1.0 / joint_axis.dot(part_inv_inertia + parent_inv_inertia)

    var lambda: float = effective_mass * (joint_axis.dot(parent_state.angular_velocity - part_state.angular_velocity) + part.desired_motor_velocity)
    lambda = clampf(lambda, -torque, torque)

    results[0] -= lambda * parent_inv_inertia
    results[1] += lambda * part_inv_inertia

func _dist_to_min_shorter(min_d: float, max_d: float) -> bool:
    min_d = absf(min_d)
    if min_d > 1.0:
        min_d = 2.0 - min_d

    max_d = absf(max_d)
    if max_d > 1.0:
        max_d = 2.0 - max_d

    return min_d < max_d

func reload_chain() -> void:
    is_valid = false
    is_ik_enabled = false
    skeleton = null
    part_list.clear()
    bone_list.clear()
    part_count = 0

    var found_skeleton: Skeleton3D = null
    var next_parent: Node = get_parent()
    while next_parent != null:
        if next_parent is Skeleton3D:
            found_skeleton = next_parent
            break
        next_parent = next_parent.get_parent()

    if not found_skeleton:
        push_error(
            (
                'PhysicalBoneChain3D %s must have a Skeleton3D as a direct ancestor when added to '
                + 'the scene tree. You must use the build method from a PhysicalSkeleton to create '
                + 'these nodes.'
            ) % get_nice_path()
        )
        return

    if not resource:
        push_error(
            (
                'PhysicalBoneChain3D %s does not have a resource assigned to it. '
                + 'You must use the build method from a PhysicalSkeleton to create these nodes.'
            ) % get_nice_path()
        )
        return

    if resource.get_unique_id() == -1:
        push_error(
            (
                'PhysicalBoneChain3D %s resource named %s at %s has not had its unique id generated yet. '
                + 'You must save the resource before it can be used.'
            ) % [get_nice_path(), resource.resource_name, resource.resource_path]
        )
        return

    var new_part_count: int = resource.part_list.size()
    if new_part_count == 0:
        push_error(
            (
                'PhysicalBoneChain3D %s (resource named %s at %s) has an empty part list, this '
                + 'should be avoided by removing the chain or giving it parts.'
            ) % [get_nice_path(), resource.resource_name, resource.resource_path]
        )
        return

    # Ensure all parts are non-null
    for index in range(new_part_count):
        var part: PhysicalBonePartResource = resource.part_list[index]
        if not part:
            push_error(
                (
                    'PhysicalBoneChain3D %s (resource named %s at %s) is missing a part at index %d, null found.'
                ) % [get_nice_path(), resource.resource_name, resource.resource_path, index]
            )
            return

    var new_bone_list: PackedInt32Array = resource.get_bone_list(found_skeleton)
    if new_bone_list.size() != new_part_count:
        push_error(
            (
                'PhysicalBoneChain3D %s (resource named %s at %s) failed to obtain bone ids for part list. '
                + 'Needed %d ids, but got %d'
            ) % [get_nice_path(), resource.resource_name, resource.resource_path, new_part_count, new_bone_list.size()]
        )
        return

    var children_part_list: Array[PhysicalBonePart3D]
    children_part_list.assign(find_children('', 'PhysicalBonePart3D'))

    var indexed_part_list: Array[PhysicalBonePart3D]
    indexed_part_list.resize(new_part_count)
    for part in children_part_list:
        if not part.is_valid:
            push_error(
                (
                    'PhysicalBoneChain3D %s found a misconfigured child PhysicalBonePart3D %s. '
                    + 'There should be additional errors above.'
                ) % [get_nice_path(), part.get_nice_path()]
            )
            return

        if part.part_index == -1:
            push_error(
                (
                    'PhysicalBoneChain3D %s found a misconfigured child PhysicalBonePart3D %s, missing '
                    + 'a part index. '
                    + 'You must use the build method from a PhysicalSkeleton to create these nodes.'
                ) % [get_nice_path(), part.get_nice_path()]
            )
            return

        if part.part_index >= new_part_count:
            push_error(
                (
                    'PhysicalBoneChain3D %s found an extra child PhysicalBonePart3D %s, part index '
                    + 'is greater than the size of the resource part list. '
                    + 'You should rebuild from a PhysicalSkeleton, or add the missing part to the '
                    + 'resource named %s at %s.'
                ) % [get_nice_path(), part.get_nice_path(), resource.resource_name, resource.resource_path]
            )
            return

        if indexed_part_list[part.part_index] != null:
            push_error(
                (
                    'PhysicalBoneChain3D %s found two child PhysicalBonePart3D which share the same '
                    + 'part index, nodes are %s and %s.'
                    + 'You should rebuild from a PhysicalSkeleton, delete the extra PhysicalBonePart3D, '
                    + 'or add the missing part to the resource named %s at %s.'
                ) % [
                    get_nice_path(), part.get_nice_path(), indexed_part_list[part.part_index].get_nice_path(),
                    resource.resource_name, resource.resource_path
                ]
            )
            return

        if not part.resource:
            push_error(
                (
                    'PhysicalBoneChain3D %s found child PhysicalBonePart3D %s which is missing a '
                    + 'resource.'
                    + 'You must use the build method from a PhysicalSkeleton to create these nodes.'
                ) % [get_nice_path(), part.get_nice_path()]
            )
            return

        if part.resource != resource.part_list[part.part_index]:
            push_error(
                (
                    'PhysicalBoneChain3D %s found misconfigured child PhysicalBonePart3D %s, the '
                    + 'internal resource does not match the chain resource definition named %s at %s. '
                    + 'You should rebuild from a PhysicalSkeleton to fix the node.'
                ) % [get_nice_path(), part.get_nice_path(), resource.resource_name, resource.resource_path]
            )
            return

        indexed_part_list[part.part_index] = part

    # Check for ik enabled parts
    for index in range(new_part_count):
        if indexed_part_list[index].resource.ik_enabled:
            is_ik_enabled = true
            break

    is_valid = true
    skeleton = found_skeleton
    bone_list = new_bone_list
    part_list = indexed_part_list
    part_count = new_part_count

    if not is_ik_enabled:
        return

    if not resource.changed.is_connected(on_ik_setting_changed):
        resource.changed.connect(on_ik_setting_changed)
        if ik_node:
            on_ik_setting_changed()

    for part in part_list:
        var binding := on_part_ik_changed.bind(part.part_index)
        if not part.resource.setting_changed.is_connected(binding):
            part.resource.setting_changed.connect(binding)
            if ik_node:
                binding.call('')
