## Maintains a system made of joints and rigid bodies for a skeleton, giving it
## physical reactions to other objects in the world
@tool
class_name PhysicalSkeleton extends SkeletonModifier3D


const META_NODE_ROOT: StringName = &'_physical_chain_root'
const META_CHAIN_RESOURCE_ID: StringName = &'_physical_chain_resource_id'


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
const JointData = preload("uid://m8gpd36535th")
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

## Node holding all the chain nodes
var _chain_node_root: Node
## Map chain uids to chain nodes
var _chain_node_map: Dictionary[int, Node]

## Array of managed JointData
var joints: Array[JointData]


var initialized: bool = false
var has_bodies: bool = false
var bodies_active: bool = false

var _cached_attachments: Array[ModifierBoneTarget3D] = []
var cached_delta: float

var chain_list: Array[PhysicalBoneChain3D]


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
        setup_body()
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

    for chain in chain_list:
        if not chain.is_valid:
            continue
        chain.update()

func activate_bodies() -> void:
    # Inherit velocity of main body
    var main_body_state := PhysicsServer3D.body_get_direct_state(main_body.get_rid())

    for chain in chain_list:
        chain.activate(main_body_state)

    bodies_active = true

func deactivate_bodies() -> void:
    for chain in chain_list:
        chain.deactivate()

    bodies_active = false

## Call this when the skeleton pose is ready to be targeted using joint motors.
## This modifier must have processed early enough to copy the physical joint
## rotations onto the skeleton pose, and save the initial rotations, so it can
## correctly target what changed in the pose.
func on_pose_finalized() -> void:
    if not bodies_active:
        return

    const ITERATIONS: int = 1
    for chain in chain_list:
        if (not chain.is_valid) or (not chain.is_powered):
            continue
        chain.setup_velocity()
        chain.solve_velocity(ITERATIONS, cached_delta)

func get_chain_node_root() -> Node:
    if not _chain_node_root:
        for node in skeleton.get_children():
            if node.get_meta(META_NODE_ROOT, false):
                _chain_node_root = node
                break

    return _chain_node_root

func build_chain(chain: PhysicalBoneChainResource, custom_joint_builder: Callable) -> void:
    pass

func setup_body() -> void:
    skeleton = get_skeleton()
    if not skeleton:
        push_error('PhysicalSkeleton could not find a skeleton!')
        return

    main_body = _find_main_body()
    if not main_body:
        push_error('PhysicalSkeleton could not find a primary RigidBody3D!')
        return

    var chain_root: Node = get_chain_node_root()
    if not chain_root:
        push_error(
            'PhysicalSkeleton could not find the chain root node, it must be built first. '
            + 'Only PhysicalBoneChain3D created by this PhysicalSkeleton that are in the '
            + 'chain root node can be loaded. You may organize the nodes however you want, '
            + 'as long as they exist somewhere in the chain root node.'
        )
        return

    chain_list.assign(chain_root.find_children('', 'PhysicalBoneChain3D'))
    if chain_list.size() == 0:
        push_error(
            'PhysicalSkeleton found no PhysicalBoneChain3D within the chain root %s. '
            + 'Only chains within this root node can be loaded, please move the nodes '
            + 'into this root or rebuild the chain. You can organize them however you '
            + 'want, as long as they are somewhere in the chain root node.'
        )
        return

    # Collect bone joint mappings for priority assignment
    var bone_joint_map: Dictionary[int, Array] = {}

    # Ensure collision exceptions for parts that initially intersect the main body
    var main_body_rid: RID = main_body.get_rid()
    var main_body_state := PhysicsServer3D.body_get_direct_state(main_body_rid)
    var space := main_body_state.get_space_state()
    var query := PhysicsShapeQueryParameters3D.new()
    query.collision_mask = PhysicsServer3D.body_get_collision_layer(main_body_rid)

    # Process chains
    for chain in chain_list:
        var chain_bone_joint_map: Dictionary[int, Array] = chain.get_bone_joint_map()

        for bone_idx in chain_bone_joint_map:
            if bone_joint_map.has(bone_idx):
                push_error(
                    (
                        'PhysicalSkeleton found duplicated PhysicalBoneChain3D %s, '
                        + 'it references the bone %s, which is already managed by '
                        + 'another chain. Please delete the duplicated node, or '
                        + 'rebuild the chains.'
                    ) % [chain.name, skeleton.get_bone_name(bone_idx)]
                )
                return

        bone_joint_map.assign(chain_bone_joint_map)

        # Process parts
        for part in chain.part_list:

            # Check current exceptions, may already include main body
            var skip: bool = false
            for excepted in part.get_collision_exceptions():
                if excepted == main_body:
                    skip = true
                    break
            if skip:
                continue

            # If the main body is intersecting this body, ensure it has a collision
            # exception. This can happen when joint bodies exist fully contained in
            # the main body, causing the next joint to not add the exception by default.

            var body_rid: RID = part.get_rid()
            var intersects_main_body: bool = false
            for body_shape in range(PhysicsServer3D.body_get_shape_count(body_rid)):
                var body_shape_rid: RID = PhysicsServer3D.body_get_shape(body_rid, body_shape)
                var shape_xform: Transform3D = PhysicsServer3D.body_get_shape_transform(body_rid, body_shape)

                query.shape_rid = body_shape_rid
                query.transform = part.global_transform * shape_xform

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
                        'PhysicalBonePart3D %s initially intersects %s, adding exception'
                    ) % [part.name, main_body.name]
                )
                part.add_collision_exception_with(main_body)
                main_body.add_collision_exception_with(part)

    var joint_priority_map: Dictionary = _calculate_joint_priority(bone_joint_map)

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
            #       impulses straight to the main body, rather than lag by N+ iterations
            joint.solver_priority = max_priority - priority

    # Initially disable bodies
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
