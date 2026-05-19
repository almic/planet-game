## Maintains a system made of joints and rigid bodies for a skeleton, giving it
## physical reactions to other objects in the world
@tool
class_name PhysicalSkeleton extends SkeletonModifier3D


@export_tool_button('Create IK Joint Bodies', 'PhysicalBoneSimulator3D')
var _btn_create_ik_joint_bodies = editor_create_ik_bodies

@export_tool_button('Update Joints', 'Generic6DOFJoint3D')
var _btn_update_joints = editor_update_joints


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
    var parent: RigidBody3D
    var body: RigidBody3D
    var joint: Generic6DOFJoint3D
    var xform_rel_parent: Transform3D
    var xform_rel_body: Transform3D

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

var _cached_attachments: Array[ModifierBoneTarget3D] = []


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


func _process_modification_with_delta(delta: float) -> void:
    if not initialized:
        setup_body_joints.call_deferred()
        initialized = true

    if not has_bodies:
        return

    for joint_data in joints:
        var gt: Transform3D = joint_data.joint.global_transform
        var parent_rt: Transform3D = joint_data.xform_rel_parent
        var body_rt: Transform3D = joint_data.xform_rel_body

        var joint_parent: Transform3D = joint_data.parent.global_transform * parent_rt
        var joint_body: Transform3D = joint_data.body.global_transform * body_rt

        # TODO
        var error: Vector3 = joint_body.origin - joint_parent.origin
        var angle: Quaternion = joint_parent.basis.get_rotation_quaternion().inverse() * joint_body.basis.get_rotation_quaternion()


        #print('error: %s\nangle: %s' % [str(error), str(angle.get_euler())])

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

    # Save all nodes to obtain exact paths later
    var path_map: Dictionary
    for joint_data in loaded_joints:
        var mapping: Array[Node]
        mapping.resize(2)
        var joint := joint_data.joint
        if joint.node_a:
            mapping[0] = joint.get_node(joint.node_a)
        if joint.node_b:
            mapping[1] = joint.get_node(joint.node_b)
        path_map.set(joint, mapping)

    # Reparent all bodies
    var scene_root: Node3D = get_tree().current_scene as Node3D
    for joint_data in loaded_joints:
        joint_data.body.reparent(scene_root)

    var main_body_state := PhysicsServer3D.body_get_direct_state(main_body.get_rid())
    for joint_data in loaded_joints:
        # Update all joint paths
        var joint := joint_data.joint
        joint.node_a = path_map.get(joint)[0].get_path()
        joint.node_b = path_map.get(joint)[1].get_path()

        # Copy processing state to bodies and joints
        joint_data.parent.process_mode = main_body.process_mode
        joint_data.body.process_mode = main_body.process_mode
        joint_data.joint.process_mode = main_body.process_mode

        # Copy velocity of main body
        var state := PhysicsServer3D.body_get_direct_state(joint_data.body.get_rid())
        var local_position: Vector3 = (state.transform.origin + state.center_of_mass) - main_body_state.transform.origin
        joint_data.body.linear_velocity = main_body_state.get_velocity_at_local_position(local_position)
        joint_data.body.angular_velocity = main_body_state.angular_velocity

    joints.clear()
    joints.assign(loaded_joints)
    has_bodies = true

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

    if target_joints.size() != 1:
        push_warning(
            (
                  'Attachment "%s" for bone %d is missing a Generic6DOFJoint3D within the RigidBody3D "%s".'
                + ' There should be exactly 1 Generic6DOFJoint3D.'
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

    var joint_data: JointData = JointData.new()
    joint_data.bone_idx = bone_idx
    joint_data.body = bone_body
    joint_data.joint = bone_joint
    joint_data.parent = parent

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
