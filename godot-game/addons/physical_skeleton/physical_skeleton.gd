## Maintains a system made of joints and rigid bodies for a skeleton, giving it
## physical reactions to other objects in the world
@tool
class_name PhysicalSkeleton extends SkeletonModifier3D


@export_tool_button('Create IK Joint Bodies', 'PhysicalBoneSimulator3D')
var _btn_create_ik_joint_bodies = editor_create_ik_bodies

@export_tool_button('Update Joints', 'Generic6DOFJoint3D')
var _btn_update_joints = editor_update_joints


## How many copies to create of the first joints in the chain. Set to zero to
## disable copies.
@export_range(0, 10, 1, 'or_greater')
var first_joint_copies: int = 3

## How many copies to create of other joints in the chain. Set to zero to
## disable copies
@export_range(0, 10, 1, 'or_greater')
var joint_copies: int = 2

## Length to spread the joints on the rotation axis
@export_range(0.0, 0.2, 0.001)
var joint_copy_width: float = 0.01


@export_group('Spring Calculator', 'calc_spring')

@export_custom(PROPERTY_HINT_RANGE, '0.001,100.0,0.001,or_greater,suffix:kg', PROPERTY_USAGE_EDITOR)
var calc_spring_effective_mass: float = 4.0:
    set(value):
        calc_spring_effective_mass = value
        editor_update_spring_calculator()

@export_custom(PROPERTY_HINT_RANGE, '0.001,100.0,0.001,or_greater,suffix:Hz', PROPERTY_USAGE_EDITOR)
var calc_spring_frequency: float = 1.2:
    set(value):
        calc_spring_frequency = value
        editor_update_spring_calculator()

@export_custom(PROPERTY_HINT_RANGE, '0.0,1.0,0.001', PROPERTY_USAGE_EDITOR)
var calc_spring_damping_ratio: float = 0.5:
    set(value):
        calc_spring_damping_ratio = value
        editor_update_spring_calculator()

@export_custom(
    PROPERTY_HINT_RANGE,
    '0.0,1.0,0.001,or_greater,hide_control',
    PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR
)
var calc_spring_stiffness: float = 0.0

@export_custom(
    PROPERTY_HINT_RANGE,
    '0.0,1.0,0.001,or_greater,hide_control',
    PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR
)
var calc_spring_damping: float = 0.0


@export_group('Frequency Calculator', 'calc_freq')

@export_custom(PROPERTY_HINT_RANGE, '0.001,100.0,0.001,or_greater', PROPERTY_USAGE_EDITOR)
var calc_freq_stiffness: float = 4.0:
    set(value):
        calc_freq_stiffness = value
        editor_update_frequency_calculator()

@export_custom(PROPERTY_HINT_RANGE, '0.001,100.0,0.001,or_greater,suffix:Hz', PROPERTY_USAGE_EDITOR)
var calc_freq_frequency: float = 1.2:
    set(value):
        calc_freq_frequency = value
        editor_update_frequency_calculator()

@export_custom(PROPERTY_HINT_RANGE, '0.0,1.0,0.001', PROPERTY_USAGE_EDITOR)
var calc_freq_damping_ratio: float = 0.5:
    set(value):
        calc_freq_damping_ratio = value
        editor_update_frequency_calculator()

@export_custom(
    PROPERTY_HINT_RANGE,
    '0.0,1.0,0.001,or_greater,hide_control',
    PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR
)
var calc_freq_damping: float = 0.0


## Contains data and object references on a joint
class JointData:
    var bone_idx: int = -1
    var bone_length: float = 0.0
    var is_ik_joint: bool = false
    var is_enabled: bool = true
    var ik_setting_idx: int = -1
    var ik_joint_idx: int = -1
    var parent: RigidBody3D
    var body: RigidBody3D
    var center_of_mass: Vector3
    var joint: Generic6DOFJoint3D
    var attachment: ModifierBoneTarget3D
    var xform_rel_parent: Transform3D
    var xform_rel_body: Transform3D
    var offset: Transform3D
    var angle: Quaternion

static var INVALID_JOINT: JointData = JointData.new()

## Emits when a joint calculates a higher force needed to match the skeleton
## than its limitations permit
signal force_exceeded(
        joint_info: JointData,
        linear_force: Vector3,
        angular_force: Vector3,
        linear_limit: float,
        angular_limit: float
)

## The skeleton driving the joints
var skeleton: Skeleton3D
## The main body of the skeleton
var main_body: RigidBody3D

## Array of managed JointData
var joints: Array[JointData]


var initialized: bool = false
var has_bodies: bool = false
var bodies_active: bool = false

var iterate_ik: IterateIK3D
var _cached_attachments: Array[ModifierBoneTarget3D] = []
var _target_to_settings: Dictionary
var cached_delta: float


func editor_create_ik_bodies() -> void:
    EditorInterface.get_editor_toaster().push_toast(
            'Functionality not implemented! TODO!',EditorToaster.SEVERITY_INFO
    )

func editor_update_joints() -> void:
    EditorInterface.get_editor_toaster().push_toast(
            'Functionality not implemented! TODO!',EditorToaster.SEVERITY_INFO
    )

func editor_update_spring_calculator() -> void:
    # Stiffness and damping force calculation from Jolt's frequency/ damping ratio
    var omega: float = TAU * calc_spring_frequency
    calc_spring_stiffness = calc_spring_effective_mass * omega * omega
    calc_spring_damping = 2.0 * calc_spring_effective_mass * calc_spring_damping_ratio * omega

func editor_update_frequency_calculator() -> void:
    # Stiffness and damping force calculation from Jolt's frequency/ damping ratio
    var omega: float = TAU * calc_freq_frequency
    var effective_mass: float = calc_freq_stiffness / (omega * omega)
    calc_freq_damping = 2.0 * effective_mass * calc_freq_damping_ratio * omega

func set_ik_modifier(ik_modifier: IterateIK3D) -> void:
    if iterate_ik and iterate_ik.modification_processed.is_connected(update_motors):
        iterate_ik.modification_processed.disconnect(update_motors)

    _target_to_settings.clear()
    iterate_ik = ik_modifier

    for i in range(iterate_ik.setting_count):
        var target_node: Node3D = iterate_ik.get_node(iterate_ik.get_target_node(i))
        _target_to_settings.set(target_node, i)

    if iterate_ik and (not iterate_ik.modification_processed.is_connected(update_motors)):
        iterate_ik.modification_processed.connect(update_motors)

func _process_modification_with_delta(delta: float) -> void:
    if not initialized:
        setup_body_joints.call_deferred()
        initialized = true

    if not has_bodies:
        return

    if active:
        if not bodies_active:
            activate_bodies()
    else:
        if bodies_active:
            deactivate_bodies()
        return

    cached_delta = delta

    var to_remove: Array[JointData]
    for joint_data in joints:

        var joint_parent: Transform3D = joint_data.parent.global_transform * joint_data.xform_rel_parent
        var joint_body: Transform3D = joint_data.body.global_transform * joint_data.xform_rel_body

        var body_diff: Transform3D = joint_parent.affine_inverse() * joint_body
        joint_data.offset = body_diff

        var offsets: PackedVector3Array = joint_data.joint.get_linear_limit()
        var error: Vector3 = body_diff.origin
        for axis in range(3):
            var lower: float = offsets[0][axis]
            var upper: float = offsets[1][axis]
            if error[axis] > upper:
                error[axis] -= upper
            elif error[axis] < lower:
                error[axis] -= lower
            else:
                error[axis] = 0

        var joint: Joint3D = joint_data.joint
        var total_force: float = 0
        if joint is BeamPivotJoint3D:
            total_force = joint.get_total_applied_force()
        elif joint is Generic6DOFJoint3D:
            var linear: float = joint.get_applied_force()
            var torque: float = joint.get_applied_torque()
            total_force = linear + torque

        if total_force > 500.0:
            print('%d : %s: %.2f' % [Engine.get_physics_frames(), joint.name, total_force])
            to_remove.append(joint_data)

        #print('error: %s\nangle: %s' % [str(error), str(angle.get_euler())])

    var to_disable: Array[RigidBody3D] = []

    for joint_data in to_remove:
        print('Breaking joint %s on %s' % [joint_data.joint.name, main_body.name])

        if joint_data.is_ik_joint and iterate_ik:
            if joint_data.ik_setting_idx < iterate_ik.setting_count:
                iterate_ik.set_target_node(joint_data.ik_setting_idx, NodePath(""))

        var index: int = joints.find(joint_data)
        joints.remove_at(index)
        joint_data.joint.queue_free()
        if joint_data.parent != main_body:
            to_disable.append(joint_data.parent)

        if index >= joints.size():
            continue

        var next_parent: RigidBody3D = joint_data.body
        var child: JointData = joints[index]

        while child.parent == next_parent:
            print('Removing joint %s' % child.body.name)
            # "kill" joint motors, set velocity to zero and use a low torque limit
            # TODO: make max force a parameter
            const DEAD_TORQUE: float = 10.0
            if child.joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR):
                child.joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0)
                child.joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, DEAD_TORQUE)
            if child.joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR):
                child.joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0)
                child.joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, DEAD_TORQUE)
            if child.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR):
                child.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0)
                child.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, DEAD_TORQUE)

            joints.remove_at(index)
            if index >= joints.size():
                break
            next_parent = child.body
            child = joints[index]

    for body in to_disable:
        for i in range(joints.size()):
            var joint_data: JointData = joints[i]
            if joint_data.body != body:
                continue

            # Already disabled this chain, nothing to do
            if not joint_data.is_enabled:
                break

            print('Disabling %s' % joint_data.body)
            joint_data.is_enabled = false

            var next_body: RigidBody3D = joint_data.parent
            while true:
                if next_body == main_body:
                    break

                i -= 1
                if i < 0:
                    break

                joint_data = joints[i]
                if joint_data.body != next_body:
                    break

                print('Disabling %s' % joint_data.body)
                joint_data.is_enabled = false
                next_body = joint_data.parent

    for joint_data in joints:
        var bone_rotation: Quaternion = joint_data.offset.basis.get_rotation_quaternion()
        joint_data.angle = bone_rotation

        bone_rotation = skeleton.get_bone_rest(joint_data.bone_idx).basis.get_rotation_quaternion() * bone_rotation
        skeleton.set_bone_pose_rotation(joint_data.bone_idx, bone_rotation)

func _snap_bone_to_rotation_axis(joint_data: JointData) -> Quaternion:
    var rotation_axis_vector: Vector3 = iterate_ik.get_joint_rotation_axis_vector(joint_data.ik_setting_idx, joint_data.ik_joint_idx)
    if rotation_axis_vector.is_zero_approx():
        return joint_data.offset.basis.get_rotation_quaternion()

    rotation_axis_vector = rotation_axis_vector.normalized()

    # When nearly aligned to the axis of rotation... must give up
    var local_vector: Vector3 = joint_data.offset.basis.y
    if is_equal_approx(absf(local_vector.dot(rotation_axis_vector)), 1.0):
        return joint_data.offset.basis.get_rotation_quaternion()

    local_vector = local_vector.slide(rotation_axis_vector).normalized()
    var axis: RotationAxis = iterate_ik.get_joint_rotation_axis(joint_data.ik_setting_idx, joint_data.ik_joint_idx)
    if axis == ROTATION_AXIS_X:
        return Basis(Vector3.RIGHT, local_vector, Vector3.RIGHT.cross(local_vector)).get_rotation_quaternion()
    elif axis == ROTATION_AXIS_Z:
        return Basis(local_vector.cross(Vector3.BACK), local_vector, Vector3.BACK).get_rotation_quaternion()
    else:
        # This one is too much, I won't be using it and I don't have anything to prove
        push_error("I'm sorry Dave, I'm afraid I can't do that.")
        return joint_data.offset.basis.get_rotation_quaternion()

func activate_bodies() -> void:
    for joint_data in joints:
        # Make body visible
        joint_data.body.visible = true

        # Copy processing state to bodies and joints
        # TODO: this causes the joint to rebuild, and probably immediately, so
        #       we may need to be sure to run through joints from root to end
        joint_data.body.process_mode = main_body.process_mode
        joint_data.joint.process_mode = main_body.process_mode

        # Teleport to joint attachment node
        joint_data.body.global_transform = joint_data.attachment.global_transform
        joint_data.body.force_update_transform()

        # Copy velocity of main body
        var main_body_state := PhysicsServer3D.body_get_direct_state(main_body.get_rid())
        var local_position: Vector3 = (joint_data.body.global_position + joint_data.center_of_mass) - main_body_state.transform.origin
        joint_data.body.linear_velocity = main_body_state.get_velocity_at_local_position(local_position)
        joint_data.body.angular_velocity = main_body_state.angular_velocity

    bodies_active = true

func deactivate_bodies() -> void:
    for joint_data in joints:
        # Hide body
        joint_data.body.visible = false

        # Copy processing state to bodies and joints
        joint_data.body.process_mode = Node.PROCESS_MODE_DISABLED
        joint_data.joint.process_mode = Node.PROCESS_MODE_DISABLED

    bodies_active = false

func update_motors() -> void:
    if not bodies_active:
        return

    const ITERATIONS: int = 1
    for i in range(ITERATIONS):
        var impulse: bool = false
        if i % 2 == 0:
            for joint_data in joints:
                if not joint_data.is_enabled:
                    continue

                var applied_impulse: bool = _solve_joint_motor(joint_data, cached_delta)
                impulse = impulse || applied_impulse
        else:
            for joint in range(joints.size() - 1, -1, -1):
                var joint_data: JointData = joints[joint]
                if not joint_data.is_enabled:
                    continue

                var applied_impulse: bool = _solve_joint_motor(joint_data, cached_delta)
                impulse = impulse || applied_impulse
        if not impulse:
            break

func _solve_joint_motor(joint_data: JointData, delta: float) -> bool:

    var target_rotation: Quaternion = skeleton.get_bone_pose_rotation(joint_data.bone_idx)
    target_rotation = skeleton.get_bone_rest(joint_data.bone_idx).basis.get_rotation_quaternion().inverse() * target_rotation

    const MAX_VELOCITY: float = 0.5

    var velocities: Vector3 = -(joint_data.angle.inverse() * target_rotation).get_euler()
    #if velocities.y > deg_to_rad(1.0):
        #breakpoint
    for i in range(3):
        if absf(velocities[i]) < 1.745e-3:
            velocities[i] = 0.0
            continue

    velocities = velocities.sign() * (velocities.abs() / delta).minf(MAX_VELOCITY)

    if velocities == Vector3.ZERO:
        return false

    # TODO: velocity calculation improvements

    if joint_data.joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR):
        joint_data.joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, velocities.x)
    if joint_data.joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR):
        joint_data.joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, velocities.y)
    if joint_data.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR):
        joint_data.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, velocities.z)

    return true

func setup_body_joints() -> void:
    # Do not modify the tree in the editor
    if Engine.is_editor_hint():
        return

    skeleton = get_skeleton()
    if not skeleton:
        push_error('PhysicalSkeleton could not find a skeleton!')
        return

    main_body = _find_main_body()
    if not main_body:
        push_error('PhysicalSkeleton could not find a primary RigidBody3D!')
        return

    var attachments: Array[ModifierBoneTarget3D] = get_bone_attachments()
    var loaded_joints: Array[JointData]

    # Start by loading IK paths
    if iterate_ik:
        for setting in range(iterate_ik.setting_count):
            for joint in range(iterate_ik.get_joint_count(setting) - 1):
                var bone_idx: int = iterate_ik.get_joint_bone(setting, joint)
                var joint_data: JointData = _make_joint_data_from_bone_idx(bone_idx, loaded_joints)

                # Badly formed joint, we should stop right away.
                if joint_data == INVALID_JOINT:
                    return

                if not joint_data:
                    continue

                joint_data.is_ik_joint = true
                joint_data.ik_setting_idx = setting
                joint_data.ik_joint_idx = joint

                var rotation_axis: RotationAxis = iterate_ik.get_joint_rotation_axis(setting, joint)
                if not (rotation_axis < ROTATION_AXIS_ALL):
                    push_error(
                        (
                            "Physical chains with IK must be limited to 1 axis of rotation! "
                            + "Setting %d on joint %d has a Rotation Axis of %s"\
                        ) % [setting, joint, str(rotation_axis)]
                    )
                    return

                var limitation: JointLimitationCone3D = iterate_ik.get_joint_limitation(setting, joint) as JointLimitationCone3D
                var limitation_angle: float = TAU
                var rotation_offset: Vector3 = Vector3.ZERO
                if limitation:
                    limitation_angle = limitation.angle
                    rotation_offset = iterate_ik.get_joint_limitation_rotation_offset(setting, joint).get_euler()

                    # Verify rotation offset is normal, should only apply on the axis of rotation
                    for i in range(3):
                        if i == rotation_axis:
                            continue
                        elif absf(rotation_offset[i]) >= 1.74e-3: # about 0.1 degrees
                            push_error(
                                (
                                    "Reading strange rotation offset for setting %d/ joint %d. Has "
                                    + "offset for axis %d but can only rotate on axis %d. Please "
                                    + "correct the rotation offset so it only spins axis %d."
                                ) % [setting, joint, i, rotation_axis, rotation_axis]
                            )
                            return

                var lower_limit: float = rotation_offset[rotation_axis] - (limitation_angle * 0.5)
                var upper_limit: float = rotation_offset[rotation_axis] + (limitation_angle * 0.5)
                if rotation_axis == ROTATION_AXIS_X:
                    joint_data.joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower_limit)
                    joint_data.joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper_limit)
                elif rotation_axis == ROTATION_AXIS_Z:
                    joint_data.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower_limit)
                    joint_data.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper_limit)
                else: # rotation_axis == ROTATION_AXIS_Y
                    joint_data.joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower_limit)
                    joint_data.joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper_limit)

                loaded_joints.append(joint_data)

    # Load any remaining attachments
    for target in attachments:
        var bone_idx: int = target.bone
        if bone_idx == -1:
            continue

        var already_loaded: bool = false
        for j in loaded_joints:
            if j.bone_idx == bone_idx:
                already_loaded = true
                break

        if already_loaded:
            continue

        var joint_data: JointData = _make_joint_data_from_bone_target(target, loaded_joints)

        if not joint_data:
            continue

        # Badly formed joint, we should stop right away.
        if joint_data == INVALID_JOINT:
            return

        loaded_joints.append(joint_data)

    if loaded_joints.size() == 0:
        return

    var bone_joint_map: Dictionary[int, Array] = {}
    for attach in attachments:
        var body_list: Array[RigidBody3D]
        body_list.assign(attach.find_children('', 'RigidBody3D', false, false))
        if body_list.size() != 1:
            continue
        var found_joints: Array[Joint3D]
        found_joints.assign(body_list[0].find_children('', 'Joint3D', false, false))
        if found_joints.size() == 0:
            continue
        bone_joint_map.set(attach.bone, found_joints)

    var joint_priority_map: Dictionary = _calculate_joint_priority(bone_joint_map)

    # Save all nodes to obtain exact paths later
    var path_map: Dictionary
    for joint_data in loaded_joints:
        var nested_joint: Array[Joint3D]
        nested_joint.assign(joint_data.body.find_children('', 'Joint3D', false, false))
        for joint in nested_joint:
            var mapping: Array[Node]
            mapping.resize(2)
            if joint.node_a:
                mapping[0] = joint.get_node(joint.node_a)
            if joint.node_b:
                mapping[1] = joint.get_node(joint.node_b)
            path_map.set(joint, mapping)

    # Reparent all bodies
    var scene_root: Node3D = get_tree().current_scene as Node3D
    for joint_data in loaded_joints:
        joint_data.body.reparent(scene_root)

    var main_body_rid: RID = main_body.get_rid()
    var main_body_state := PhysicsServer3D.body_get_direct_state(main_body_rid)
    var space := main_body_state.get_space_state()
    var query := PhysicsShapeQueryParameters3D.new()
    query.collision_mask = PhysicsServer3D.body_get_collision_layer(main_body_rid)

    for joint_data in loaded_joints:
        # Update all joint paths
        var nested_joint: Array[Joint3D]
        # NOTE: must have owner set to false, reparenting breaks owners somehow...
        nested_joint.assign(joint_data.body.find_children('', 'Joint3D', false, false))
        for joint in nested_joint:
            # Move joint up axis if copies should be made
            if (
                        joint == joint_data.joint
                    and joint_data.is_ik_joint
                    and (
                           (joint_data.ik_joint_idx == 0 and first_joint_copies > 0)
                        or (joint_data.ik_joint_idx > 0 and joint_copies > 0)
                    )
            ):
                joint.position += 0.5 * joint_copy_width * iterate_ik.get_joint_rotation_axis_vector(joint_data.ik_setting_idx, joint_data.ik_joint_idx)

            var node_list: Array[Node] = path_map.get(joint, [null, null])
            if node_list[0]:
                joint.node_a = node_list[0].get_path()
            if node_list[1]:
                joint.node_b = node_list[1].get_path()

        # Store center of mass
        # NOTE: when enabling after being disabled, physics state isn't ready yet,
        #       so we have to cache now before it is disabled.
        joint_data.center_of_mass = PhysicsServer3D.body_get_param(joint_data.body.get_rid(), PhysicsServer3D.BODY_PARAM_CENTER_OF_MASS)

        # If the main body is intersecting this body, ensure it has a collision
        # exception. This can happen when joint bodies exist fully contained in
        # the main body, causing the next joint to not add the exception by default.
        if joint_data.parent == main_body:
            continue

        var body_rid: RID = joint_data.body.get_rid()
        var intersects_main_body: bool = false
        for body_shape in range(PhysicsServer3D.body_get_shape_count(body_rid)):
            var body_shape_rid: RID = PhysicsServer3D.body_get_shape(body_rid, body_shape)
            var shape_xform: Transform3D = PhysicsServer3D.body_get_shape_transform(body_rid, body_shape)

            query.shape_rid = body_shape_rid
            query.transform = joint_data.body.global_transform * shape_xform

            var intersections: Array[Dictionary] = space.intersect_shape(query, 8)
            for hit in intersections:
                if hit.rid == main_body_rid:
                    intersects_main_body = true
                    break

            if intersects_main_body:
                break

        if intersects_main_body:
            print(
                (
                    'Joint body %s initially intersects %s, adding exception'
                ) % [joint_data.body.name, main_body.name]
            )
            joint_data.body.add_collision_exception_with(main_body)
            main_body.add_collision_exception_with(joint_data.body)

    # Duplicate joints to improve rigidity
    for i in range(maxi(first_joint_copies, joint_copies)):
        bone_joint_map.clear()
        for joint_data in loaded_joints:
            if joint_data.ik_joint_idx == 0 and i >= first_joint_copies:
                continue
            if joint_data.ik_joint_idx > 0 and i >= joint_copies:
                continue

            var joint_step: Vector3 = iterate_ik.get_joint_rotation_axis_vector(joint_data.ik_setting_idx, joint_data.ik_joint_idx)

            if joint_data.ik_joint_idx == 0:
                joint_step *= joint_copy_width / float(first_joint_copies)
            else:
                joint_step *= joint_copy_width / float(joint_copies)

            var pair_joint := _duplicate_joint(joint_data)
            if not bone_joint_map.has(joint_data.bone_idx):
                bone_joint_map.set(joint_data.bone_idx, Array())
            bone_joint_map.get(joint_data.bone_idx).append(pair_joint)

            pair_joint.position += joint_step * (i + 1)
            joint_data.body.add_child(pair_joint)

        var block_map: Dictionary = _calculate_joint_priority(bone_joint_map)
        var max_priority: int = block_map.get(&'priority')
        # Move all joints up
        var new_priority_map: Dictionary = {}
        for p in joint_priority_map:
            if p is not int:
                continue
            new_priority_map.set(p + max_priority, joint_priority_map.get(p))
        new_priority_map.set(&'priority', max_priority + joint_priority_map.get(&'priority'))
        joint_priority_map.clear()
        for k in block_map:
            if k is not int:
                continue
            new_priority_map.set(k, block_map.get(k))
        joint_priority_map = new_priority_map

    # Reverse priorities so earlier joints solve later, improving chain accuracy
    var max_priority: int = joint_priority_map.get(&'priority')
    for priority in joint_priority_map:
        if priority is not int:
            continue
        var joint_list: Array[Joint3D]
        joint_list.assign(joint_priority_map.get(priority))
        for joint in joint_list:
            # NOTE: i cannot demonstrate that this is better than not reversing priority...
            #       but logically it should as the first iteration will send lower leg
            #       impulses straight to the main body, rather than lag by 3+ iterations
            joint.solver_priority = max_priority - priority

    joints.clear()
    joints.assign(loaded_joints)

    # Initially disable joints
    deactivate_bodies()

    has_bodies = true

func _duplicate_joint(joint_data: JointData) -> Joint3D:
    var pair_joint: Shared6DOFJoint = joint_data.joint.duplicate()

    # Turn off any motors
    pair_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
    pair_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
    pair_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)

    return pair_joint

## Travels up the scene tree until it finds the first RigidBody3D
func _find_main_body() -> RigidBody3D:
    var parent: Node = get_parent()
    while parent:
        if parent is RigidBody3D:
            return parent
        parent = parent.get_parent()
    return null

func get_bone_attachments(force_reload: bool = false) -> Array[ModifierBoneTarget3D]:
    if force_reload or _cached_attachments.size() == 0:
        _cached_attachments.clear()
        _cached_attachments.assign(skeleton.find_children('', 'ModifierBoneTarget3D', false))
    return _cached_attachments

func _make_joint_data_from_bone_target(target: ModifierBoneTarget3D, loaded_joints: Array[JointData]) -> JointData:
    if not target:
        return INVALID_JOINT

    var bone_idx: int = target.bone
    if bone_idx == -1:
        return INVALID_JOINT

    # Expect at most 1 rigid body child
    var target_bodies: Array[RigidBody3D]
    target_bodies.assign(target.find_children('', 'RigidBody3D', false))

    if target_bodies.size() == 0:
        return null
    elif target_bodies.size() > 1:
        push_warning(
            (
                'Attachment "%s" for bone %d has multiple RigidBody3D children. There should be at most 1.'
            ) % [
                target.name, bone_idx
            ]
        )
        return INVALID_JOINT

    var bone_body: RigidBody3D = target_bodies[0]

    # Expect exactly one 6DOF joint
    var target_joints: Array[Generic6DOFJoint3D]
    target_joints.assign(bone_body.find_children('', 'Generic6DOFJoint3D', false))

    if target_joints.size() < 1:
        push_warning(
            (
                  'Attachment "%s" for bone %d is missing a Generic6DOFJoint3D within the RigidBody3D "%s".'
                + ' There should be at least 1 Generic6DOFJoint3D.'
            ) % [
                target.name, bone_idx, bone_body.name
            ]
        )
        return INVALID_JOINT

    var bone_joint: Generic6DOFJoint3D = target_joints[0]

    if not bone_joint.node_b:
        bone_joint.node_b = bone_joint.get_path_to(bone_body)
    elif bone_joint.get_node(bone_joint.node_b) != bone_body:
        push_warning(
            (
                  'Attachment "%s" for bone %d has the joint\'s Node B assigned to a body other than "%s".'
                + ' The joint\'s Node B must be the RigidBody3D "%s".'
            ) % [
                target.name, bone_idx, bone_body.name, bone_body.name
            ]
        )
        return INVALID_JOINT

    if not bone_joint.node_a:
        var parent_bone: int = skeleton.get_bone_parent(bone_idx)
        if bone_idx == -1:
            bone_joint.node_a = bone_joint.get_path_to(main_body)
        else:
            var joint_data: JointData = _make_joint_data_from_bone_idx(bone_idx, loaded_joints)

            if joint_data == INVALID_JOINT:
                return INVALID_JOINT

            if joint_data:
                bone_joint.node_a = bone_joint.get_path_to(joint_data.body)
            else:
                bone_joint.node_a = bone_joint.get_path_to(main_body)
    else:
        var joint_target: Node = bone_joint.get_node(bone_joint.node_a)
        if joint_target != main_body:
            # Ensure the target node is a RigidBody3D and has already been loaded, otherwise load it now
            if joint_target is not RigidBody3D:
                push_warning(
                    (
                        'Attachment "%s" for bone %d has the joint\'s Node A assigned to a node which isn\'t a RigidBody3D.'
                        + ' The joint\'s Node A must be the main body or another RigidBody3D.'
                    ) % [
                        target.name, bone_idx
                    ]
                )
                return INVALID_JOINT

            var joint_target_parent: Node = joint_target.get_parent()
            if joint_target_parent is ModifierBoneTarget3D:
                if joint_target_parent.get_skeleton() != skeleton:
                    var target_skel: Skeleton3D = joint_target_parent.get_skeleton()
                    var skel_name: String
                    if not target_skel:
                        skel_name = "Missing Skeleton"
                    else:
                        skel_name = target_skel.name

                    push_warning(
                        (
                            'Attachment "%s" for bone %d has the joint\'s Node A assigned to RigidBody3D "%s"'
                            + ' whose parent ModifierBoneTarget3D is from a different skeleton "%s".'
                            + ' The joint\'s Node A must be a RigidBody3D attached to a ModifierBoneTarget3D for this skeleton "%s".'
                        ) % [
                            target.name, bone_idx, joint_target.name, skel_name, skeleton.name
                        ]
                    )
                    return INVALID_JOINT
            else:
                push_warning(
                    (
                        'Attachment "%s" for bone %d has the joint\'s Node A assigned to RigidBody3D "%s" whose parent is not a ModifierBoneTarget3D.'
                        + ' The joint\'s Node A must be a RigidBody3D attached to a ModifierBoneTarget3D.'
                    ) % [
                        target.name, bone_idx, joint_target.name
                    ]
                )
                return INVALID_JOINT

            # Test if this target is already loaded
            var joint_target_loaded: bool = false
            for joint in loaded_joints:
                if joint.bone_idx == joint_target_parent.bone:
                    joint_target_loaded = true
                    break

            if not joint_target_loaded:
                # Must load here
                var joint_target_data: JointData = _make_joint_data_from_bone_target(joint_target_parent, loaded_joints)
                if joint_target_data == INVALID_JOINT:
                    return
                if not joint_target_data:
                    push_warning(
                        (
                            'Attachment "%s" for bone %d has the joint\'s Node A assigned to RigidBody3D "%s",'
                            + ' but failed when trying to create JointData for it. This should not have happened.'
                        ) % [
                            target.name, bone_idx, joint_target.name
                        ]
                    )
                    return INVALID_JOINT
                loaded_joints.append(joint_target_data)

    var parent: RigidBody3D = bone_joint.get_node(bone_joint.node_a) as RigidBody3D

    # Obtain a length by finding an IK setting with this bone in the chain, using the next bone as the length
    var length: float = 0.5
    var found: bool = false
    for setting in range(iterate_ik.setting_count):
        for joint in range(iterate_ik.get_joint_count(setting)):
            if bone_idx == iterate_ik.get_joint_bone(setting, joint):
                var length_bone: int = iterate_ik.get_joint_bone(setting, joint + 1)
                length = skeleton.get_bone_pose_position(length_bone).length()
                found = true
                break
        if found:
            break
    if not found:
        push_warning(
            (
                'Attachment "%s" for bone %d does not have a setting in the IterateIK3D. Unable '
                + 'to calculate a bone length, which is needed for motor displacement limits. '
                + 'Using a default length of %.2f.'
            ) % [
                target.name, bone_idx, length
            ]
        )

    var joint_data: JointData = JointData.new()
    joint_data.bone_idx = bone_idx
    joint_data.bone_length = length
    joint_data.body = bone_body
    joint_data.joint = bone_joint
    joint_data.parent = parent
    joint_data.attachment = target

    joint_data.xform_rel_body = bone_body.global_transform.affine_inverse() * bone_joint.global_transform
    joint_data.xform_rel_parent = parent.global_transform.affine_inverse() * bone_joint.global_transform

    return joint_data

## Creates a joint from a bone id, searching for a ModifierBoneTarget3D with the matching bone.
## This calls _make_joint_data_from_bone_target() when a target is found, which is used to allow
## arbitrary ordering of targets in the scene when initializing
func _make_joint_data_from_bone_idx(bone_idx: int, loaded_joints: Array[JointData]) -> JointData:
    if bone_idx == -1:
        return INVALID_JOINT

    # Test if loaded joints already has this bone idx
    for joint in loaded_joints:
        if joint.bone_idx == bone_idx:
            return joint

    var attachments: Array[ModifierBoneTarget3D] = get_bone_attachments()

    for target in attachments:
        if target.bone == bone_idx:
            return _make_joint_data_from_bone_target(target, loaded_joints)

    return null

func _calculate_joint_priority(bone_joint_map: Dictionary[int, Array]) -> Dictionary:
    var joint_priority_map: Dictionary
    var search: PackedInt32Array = [0]
    var expand: PackedInt32Array = []
    var next: PackedInt32Array = []
    var priority: int = 0

    var joint_collection: Array[Array]
    var max_priority: int = 0
    while search.size() > 0:
        for bone_idx in search:
            if bone_joint_map.has(bone_idx):
                var found_joints: Array[Joint3D]
                found_joints.assign(bone_joint_map.get(bone_idx))
                if found_joints.size() == 0:
                    expand.append(bone_idx)
                    continue

                joint_collection.append(found_joints)
                max_priority = maxi(max_priority, found_joints.size())
                next.append(bone_idx)
                continue
            expand.append(bone_idx)

        if expand.size() > 0:
            search.clear()
            for bone_idx in expand:
                search.append_array(skeleton.get_bone_children(bone_idx))
            expand.clear()
            continue

        # Add all joints to this layer
        for joint_list in joint_collection:
            var p: int = priority
            for joint in joint_list:
                if not joint_priority_map.has(p):
                    joint_priority_map.set(p, Array())
                joint_priority_map.get(p).append(joint)
                p += 1
        joint_collection.clear()
        priority += max_priority
        max_priority = 0

        search.clear()
        for bone_idx in next:
            search.append_array(skeleton.get_bone_children(bone_idx))
        next.clear()

    joint_priority_map.set(&'priority', priority)
    return joint_priority_map
