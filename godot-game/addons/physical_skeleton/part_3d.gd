@tool
class_name PhysicalBonePart3D extends RigidBody3D


const META_CUSTOM_INDEX: StringName = &'_part_custom_index'
const META_BONE_JOINT: StringName = &'_part_bone_joint'
const META_BONE_MESH: StringName = &'_part_bone_mesh'
const META_BREAK_FORCE: StringName = &'_part_break_force'


## Contains data and object references on a joint
class JointData:
    var is_breakable: bool = false
    var is_destroyed: bool = false
    var joint: Generic6DOFJoint3D

    var parent: RID
    var xform_rel_parent: Transform3D
    var xform_rel_body: Transform3D
    var offset: Transform3D


## The resource assigned to this part
@export_custom(
    PROPERTY_HINT_NONE,
    '',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var resource: PhysicalBonePartResource
## Set by PhysicalBoneChain3D when creating new parts, to skip the ready method
var _skip_ready: bool = false

## The index of this part, corresponds to the index it was created with from a
## PhysicalBoneChainResource
@export_custom(
    PROPERTY_HINT_NONE,
    '',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var part_index: int


var is_valid: bool = false

## The motor can no longer function due to damage and is in friction-only mode
var is_motor_broken: bool = false
## The motor is actively powered
var is_motor_powered: bool = false
## This part is powered, managed by the chain
var is_powered: bool = false
## This part can transfer power, determined by this part's health status
var is_power_interrupted: bool = true
## This part is using power, set to false when motors are disabled/ destroyed
var is_using_power: bool = false

## List of managed joints, read-only
var joint_list: Array[Joint3D]
## Internal joint data, read-only
var joint_data_list: Array[JointData]
## The joint data representing the bone this part is connected to
var bone_joint_data: JointData
## The main bone joint
var bone_joint: Generic6DOFJoint3D
## The collision shape of this part
var collider: CollisionShape3D
## The mesh of the part
var mesh_inst: MeshInstance3D
## The mesh which takes on the position of the bone for this part, it's location
## is handled by the PhysicalBoneChain3D
var mesh_bone_inst: MeshInstance3D

## Cached center of mass, set before disabling the body, used by chain to assign
## the correct initial linear velocity when activating the body
var _cached_com: Vector3

var joint_force_exceeded_emit: Callable
var _signal_should_break: bool = false


func _ready() -> void:
    if _skip_ready:
        return

    var xform: Transform3D = global_transform
    top_level = not Engine.is_editor_hint()
    reload_part()

    if is_valid:
        connect_resource()

func _enter_tree() -> void:
    connect_resource()

func _exit_tree() -> void:
    # I think remaining connected has the effect of retaining them in memory,
    # and still receiving signals. I wish signal connections were weak refs.
    disconnect_resource()

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

func activate() -> void:
    visible = true
    process_mode = Node.PROCESS_MODE_INHERIT

func deactivate() -> void:
    # Save our center of mass for later
    _cached_com = PhysicsServer3D.body_get_param(get_rid(), PhysicsServer3D.BODY_PARAM_CENTER_OF_MASS)
    visible = false
    process_mode = Node.PROCESS_MODE_DISABLED

## Return a read-only reference to the internal joint list managed by this part
func get_joint_list() -> Array[Joint3D]:
    return joint_list

func build_part(
        chain: PhysicalBoneChain3D,
        main_body: RigidBody3D,
        parent_body: RigidBody3D,
        custom_joint_builder: Callable
) -> bool:

    var mesh_node := MeshInstance3D.new()
    mesh_node.name = 'PartMesh'
    mesh_node.set_meta(PhysicalSkeleton.META_OWNED, true)
    add_child(mesh_node, true)
    mesh_node.owner = owner

    var collision_shape := CollisionShape3D.new()
    collision_shape.set_meta(PhysicalSkeleton.META_OWNED, true)
    add_child(collision_shape, true)
    collision_shape.owner = owner

    var main_joint := Generic6DOFJoint3D.new()
    main_joint.name = 'BoneJoint'
    main_joint.set_meta(PhysicalSkeleton.META_OWNED, true)
    main_joint.set_meta(META_BONE_JOINT, true)
    add_child(main_joint, true)
    main_joint.owner = owner
    main_joint.node_a = main_joint.get_path_to(parent_body)
    main_joint.node_b = main_joint.get_path_to(self)

    # Custom joints
    if resource.custom_enabled:
        if not custom_joint_builder.is_valid():
            push_warning(
                (
                    'PhysicalBonePart3D at %s has custom joint resources defined, '
                    + 'but was not built with a custom joint loader, so custom '
                    + 'joints will not be created. Delete the custom joint resources '
                    + 'or rebuild the chain at %s providing a custom joint loader.'
                ) % [get_nice_path(), chain.get_nice_path()]
            )
            return true

        for index in range(resource.custom_joint_resource_list.size()):
            var custom: Resource = resource.custom_joint_resource_list[index]

            if not custom:
                push_error(
                    (
                        'PhysicalBonePart3D at %s has a misconfigured custom resource '
                        + 'list named %s at %s, the index %d is null. Please add the '
                        + 'missing custom resource, or remove it from the list and '
                        + 'rebuild the chain at %s.'
                    ) % [
                        get_nice_path(),
                        resource.resource_name, resource.resource_path,
                        index,
                        chain.get_nice_path()
                    ]
                )
                return false

            var joint: Joint3D = custom_joint_builder.call(
                    chain, self, main_body, parent_body, custom
            )

            if not joint:
                push_error(
                    (
                        'PhysicalBonePart3D at %s has custom joints defined, but the '
                        + 'builder failed to create a joint for the resource named '
                        + '%s (at %s). Either remove the custom joint resource, or '
                        + 'fix the cause of the builder failure.'
                    ) % [get_nice_path(), custom.resource_name, custom.resource_path]
                )
                return false

            if joint.has_meta(META_CUSTOM_INDEX):
                push_error(
                    (
                        'PhysicalBonePart3D at %s was provided a custom joint builder '
                        + 'that has applied the meta data "%s". This name is used by '
                        + 'PhysicalBonePart3D to track and maintain custom resource '
                        + 'indices when loading or re-ordering the joints. You must '
                        + 'not use this name for meta data on custom built joints.'
                    ) % [get_nice_path(), META_CUSTOM_INDEX]
                )
                return false

            joint.set_meta(PhysicalSkeleton.META_OWNED, true)
            joint.set_meta(META_CUSTOM_INDEX, index)
            add_child(joint, true)
            joint.owner = owner

            # Make joint paths relative
            joint.node_a = joint.get_path_to(joint.get_node_or_null(joint.node_a))
            joint.node_b = joint.get_path_to(joint.get_node_or_null(joint.node_b))

    # Reload the part data, possibly causing errors
    reload_part()

    connect_resource()
    resource_modified()

    return true

func _build_mesh_bone_inst() -> MeshInstance3D:
    var bone_mesh_node = MeshInstance3D.new()
    bone_mesh_node.name = 'BoneMesh'
    bone_mesh_node.set_meta(PhysicalSkeleton.META_OWNED, true)
    bone_mesh_node.set_meta(META_BONE_MESH, true)
    return bone_mesh_node

## Creates and adds the mesh bone instance as an unowned child if needed, or
## frees the node if it is not needed
func _ensure_mesh_bone_inst() -> void:
    if resource.bone_enable_mesh:
        if mesh_bone_inst:
            return
        mesh_bone_inst = _build_mesh_bone_inst()
        add_child(mesh_bone_inst, true)
        mesh_bone_inst.material_override = resource.bone_material_override
        mesh_bone_inst.mesh = resource.bone_mesh_override
        if not mesh_bone_inst.mesh:
            mesh_bone_inst.mesh = resource.mesh
        mesh_bone_inst.position = resource.mesh_offset
        mesh_bone_inst.basis = resource.mesh_rotation
    elif mesh_bone_inst:
        mesh_bone_inst.queue_free()
        mesh_bone_inst = null

func prepare_custom_joints(custom_joint_callable: Callable) -> bool:
    if not custom_joint_callable.is_valid():
        push_error(
            (
                'PhysicalBonePart3D at %s method `prepare_custom_joints()` called '
                + 'without a valid custom joint callable. Returning false.'
            ) % get_nice_path()
        )
        return false

    for index in range(1, joint_list.size()):
        var joint: Joint3D = joint_list[index]
        var resource_index: int = joint.get_meta(META_CUSTOM_INDEX, -1)
        if resource_index < 0:
            push_error(
                (
                    'PhysicalBonePart3D at %s has a misconfigured custom joint at %s, '
                    + 'please rebuild the chain.'
                ) % [get_nice_path(), get_nice_path(joint)]
            )
            return false

        if resource_index >= resource.custom_joint_resource_list.size():
            push_error(
                (
                    'PhysicalBonePart3D at %s has a misconfigured joint at %s, '
                    + 'it expects a custom resource at index %d of the resource '
                    + 'named %s at %s, but the list is size %d. Please add the '
                    + 'missing custom resource, or rebuild the chain.'
                ) % [
                    get_nice_path(), get_nice_path(joint),
                    resource_index,
                    resource.resource_name, resource.resource_path,
                    resource.custom_joint_resource_list.size(),
                ]
            )
            return false

        var custom_resource: Resource = resource.custom_joint_resource_list[resource_index]
        if not custom_resource:
            push_error(
                (
                    'PhysicalBonePart3D at %s has a misconfigured custom resource '
                    + 'list named %s at %s, the index %d is null. Please add the '
                    + 'missing custom resource, or remove it from the list and '
                    + 'rebuild the chain.'
                ) % [
                    get_nice_path(),
                    resource.resource_name, resource.resource_path,
                    resource_index,
                ]
            )
            return false

        var success: bool = custom_joint_callable.call(joint, custom_resource)

        if not success:
            push_error(
                (
                    'PhysicalBonePart3D at %s received `false` return value from '
                    + 'the custom joint callable. The custom joint resource is '
                    + 'named %s at %s. Please fix any errors causing the loader '
                    + 'to return `false`, or try rebuilding the chain.'
                ) % [
                    get_nice_path(),
                    custom_resource.resource_name,
                    custom_resource.resource_path,
                ]
            )
            return false

    return true

func update(skeleton: Skeleton3D, bone_idx: int) -> void:
    if not bone_joint_data.is_destroyed:
        _update_joint(bone_joint_data)

        var bone_rotation: Quaternion = skeleton.get_bone_rest(bone_idx).basis.get_rotation_quaternion() * bone_joint_data.offset.basis.get_rotation_quaternion()
        skeleton.set_bone_pose_rotation(bone_idx, bone_rotation)

        if bone_joint_data.is_breakable and _should_break(bone_joint_data.joint, bone_joint_data.offset):
            print('Breaking joint %s' % [get_nice_path(bone_joint)])
            is_motor_broken = true
            is_motor_powered = false
            bone_joint_data.is_destroyed = true
            bone_joint.queue_free()
            bone_joint = null
            bone_joint_data.joint = null

        if not bone_joint_data.is_destroyed:
            _update_motor_torque()

        is_using_power = is_motor_powered

    for i in range(1, joint_data_list.size()):
        var joint_data: JointData = joint_data_list[i]

        if joint_data.is_destroyed or (not joint_data.is_breakable):
            continue

        _update_joint(joint_data)

        if _should_break(joint_data.joint, joint_data.offset):
            print('Breaking joint %s' % [get_nice_path(joint_data.joint)])
            joint_data.is_destroyed = true
            joint_data.joint.queue_free()
            joint_data.joint = null

func _update_joint(joint_data: JointData) -> void:
    var parent_state := PhysicsServer3D.body_get_direct_state(joint_data.parent)
    var joint_parent: Transform3D = parent_state.transform * joint_data.xform_rel_parent
    var joint_body: Transform3D = global_transform * joint_data.xform_rel_body

    var body_diff: Transform3D = joint_parent.affine_inverse() * joint_body
    joint_data.offset = body_diff

func _update_motor_torque() -> void:
    var motor_should_be_powered: bool = is_powered and (not is_motor_broken)
    if is_motor_powered == motor_should_be_powered:
        return

    is_motor_powered = motor_should_be_powered
    var torque_limit: float
    if is_motor_powered:
        torque_limit = resource.torque_powered
    else:
        torque_limit = resource.torque_unpowered

    var motor_axis: IterateIK3D.RotationAxis = IterateIK3D.ROTATION_AXIS_ALL

    # Setting only the limitation axis
    if resource.ik_enabled:
        motor_axis = resource.rotation_axis

    var all: bool = motor_axis >= IterateIK3D.ROTATION_AXIS_ALL

    if all or motor_axis == IterateIK3D.ROTATION_AXIS_X:
        bone_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, torque_limit)
    if all or motor_axis == IterateIK3D.ROTATION_AXIS_Y:
        bone_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, torque_limit)
    if all or motor_axis == IterateIK3D.ROTATION_AXIS_Z:
        bone_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, torque_limit)

func _should_break(joint: Joint3D, displacement: Transform3D) -> bool:
    var total_force: float = 0
    if joint is BeamPivotJoint3D:
        total_force = joint.get_total_applied_force()
    elif joint is Generic6DOFJoint3D:
        var linear: float = joint.get_applied_force()
        var torque: float = joint.get_applied_torque()
        total_force = linear + torque

    var max_force: float = joint.get_meta(META_BREAK_FORCE, 0.0)

    if total_force > max_force:
        if resource.break_use_signal:
            _signal_should_break = false
            joint_force_exceeded_emit.call(joint, total_force, max_force, self)
            return _signal_should_break
        return true

    #print('error: %s\nangle: %s' % [displacement.origin, displacement.basis.get_euler()])

    return false

func set_should_break() -> void:
    _signal_should_break = true

func on_pose_finalized(skeleton: Skeleton3D, bone_idx: int) -> void:
    _ensure_mesh_bone_inst()
    if not mesh_bone_inst:
        return

    var bone_xform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)

    mesh_bone_inst.global_transform = bone_xform
    mesh_bone_inst.position += resource.mesh_offset
    #mesh_bone_inst.basis = Basis(resource.mesh_rotation) * mesh_bone_inst.basis

func setup_motor_velocity(skeleton: Skeleton3D, bone_idx: int) -> void:
    """
    var target_rotation: Quaternion = skeleton.get_bone_pose_rotation(joint_data.bone_idx)
    target_rotation = skeleton.get_bone_rest(joint_data.bone_idx).basis.get_rotation_quaternion().inverse() * target_rotation
    """
    pass

func solve_motor_velocity(delta: float) -> bool:
    """
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
    """

    return false

func reload_part() -> void:
    is_valid = false

    bone_joint = null
    bone_joint_data = null

    collider = null

    mesh_inst = null
    mesh_bone_inst = null

    joint_list = []
    joint_data_list = []

    var joint_node_list: Array[Joint3D]
    joint_node_list.assign(find_children('', 'Joint3D'))

    var loaded_bone_joint_data: JointData
    var loaded_joint_data_list: Array[JointData]
    var loaded_joint_list: Array[Joint3D]

    for joint in joint_node_list:
        if not joint.has_meta(PhysicalSkeleton.META_OWNED):
            continue

        if joint.has_meta(META_BONE_JOINT):
            if loaded_bone_joint_data:
                push_error(
                    (
                        'PhysicalBonePart3D at %s has a duplicated bone joint %s. '
                        + 'Please delete the duplicated joint, or rebuild the chain.'
                    ) % [get_nice_path(), get_nice_path(joint)]
                )
                return
            if joint.has_meta(META_CUSTOM_INDEX):
                push_error(
                    (
                        'PhysicalBonePart3D at %s has a misconfigured bone joint %s. '
                        + 'It is marked as both the bone joint and a custom joint. '
                        + 'I don\'t know how you did this, please rebuild the chain.'
                    ) % [get_nice_path(), get_nice_path(joint)]
                )
                return
            if joint is not Generic6DOFJoint3D:
                push_error(
                    (
                        'PhysicalBonePart3D at %s has the wrong type of bone joint %s. '
                        + 'The type should be Generic6DOFJoint3D, please rebuild the chain.'
                    ) % [get_nice_path(), get_nice_path(joint)]
                )
                return
            var data: JointData = _configure_joint(joint)
            if not data:
                # Error already printed
                return
            loaded_bone_joint_data = data
            loaded_joint_data_list.insert(0, loaded_bone_joint_data)
            loaded_joint_list.insert(0, joint)
            continue
        elif not joint.has_meta(META_CUSTOM_INDEX):
            push_error(
                (
                    'PhysicalBonePart3D at %s has unknown joint %s. '
                    + 'Please delete the joint, move it elsewhere, or rebuild the chain.'
                ) % [get_nice_path(), get_nice_path(joint)]
            )
            return

        # At this point, it is a custom joint
        var data: JointData = _configure_joint(joint)
        if not data:
            # Error already printed
            return
        loaded_joint_data_list.append(data)
        loaded_joint_list.append(joint)

    var loaded_collider: CollisionShape3D
    var loaded_mesh_inst: MeshInstance3D
    var loaded_mesh_bone_inst: MeshInstance3D

    var search_list: Array[Node] = get_children(true)
    var next_search: Array[Node] = []
    while search_list.size() > 0 or next_search.size() > 0:
        var child: Node = search_list.pop_back()
        if not child:
            search_list = next_search
            next_search = []
            continue

        next_search.append_array(child.get_children())

        if not child.has_meta(PhysicalSkeleton.META_OWNED):
            continue

        if child is CollisionShape3D:
            if loaded_collider:
                # TODO: error here
                push_error('collider')
                return

            loaded_collider = child
            continue

        if child is MeshInstance3D:
            if child.has_meta(META_BONE_MESH):
                if loaded_mesh_bone_inst:
                    # TODO: error here
                    push_error('bone mesh')
                    return
                loaded_mesh_bone_inst = child
                continue
            # Must be the normal mesh
            if loaded_mesh_inst:
                # TODO: error here
                push_error('mesh inst')
                return
            loaded_mesh_inst = child
            continue

    is_valid = true

    bone_joint_data = loaded_bone_joint_data
    bone_joint = bone_joint_data.joint

    collider = loaded_collider

    joint_list = loaded_joint_list
    joint_list.make_read_only()
    joint_data_list = loaded_joint_data_list
    joint_data_list.make_read_only()

    mesh_inst = loaded_mesh_inst
    mesh_bone_inst = loaded_mesh_bone_inst

    # This is not an owned node, and is for debugging, so this is okay.
    _ensure_mesh_bone_inst()

func _configure_joint(joint: Joint3D) -> JointData:

    var joint_data: JointData = JointData.new()
    joint_data.is_breakable = joint.has_meta(META_BREAK_FORCE)

    joint_data.joint = joint
    var parent: RigidBody3D = joint.get_node(joint.node_a) as RigidBody3D
    if not parent:
        push_error(
            (
                'PhysicalBonePart3D at %s failed to configure the joint at %s, '
                + 'unable to find the parent body with path "%s".'
            ) % [get_nice_path(), get_nice_path(joint), joint.node_a]
        )
        return null

    joint_data.parent = parent.get_rid()

    joint_data.xform_rel_body = global_transform.affine_inverse() * joint.global_transform
    joint_data.xform_rel_parent = parent.global_transform.affine_inverse() * joint.global_transform

    return joint_data

func connect_resource() -> void:
    if (not resource) or resource.setting_changed.is_connected(resource_modified):
        return
    resource.setting_changed.connect(resource_modified)

func disconnect_resource() -> void:
    if (not resource) or (not resource.setting_changed.is_connected(resource_modified)):
        return
    resource.setting_changed.disconnect(resource_modified)

func resource_modified(setting: StringName = &'') -> void:
    physics_material_override = resource.physics_material
    continuous_cd = resource.continuous_cd
    collision_layer = resource.collision_layer
    collision_mask = resource.collision_mask

    mesh_inst.mesh = resource.mesh
    mesh_inst.position = resource.mesh_offset
    mesh_inst.basis = resource.mesh_rotation

    _ensure_mesh_bone_inst()

    if resource.break_enabled:
        bone_joint.set_meta(META_BREAK_FORCE, resource.break_max_force)
    else:
        bone_joint.remove_meta(META_BREAK_FORCE)

    # GODOT PLEASE
    #region linear
    bone_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, resource.joint_linear_limit_x_enabled)
    bone_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, resource.joint_linear_limit_x_lower)
    bone_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, resource.joint_linear_limit_x_upper)

    bone_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, resource.joint_linear_limit_y_enabled)
    bone_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, resource.joint_linear_limit_y_lower)
    bone_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, resource.joint_linear_limit_y_upper)

    bone_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, resource.joint_linear_limit_z_enabled)
    bone_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, resource.joint_linear_limit_z_lower)
    bone_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, resource.joint_linear_limit_z_upper)
    #endregion linear
    #region angular
    bone_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, resource.joint_angular_limit_x_enabled)
    bone_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, resource.joint_angular_limit_x_lower)
    bone_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, resource.joint_angular_limit_x_upper)

    bone_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, resource.joint_angular_limit_y_enabled)
    bone_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, resource.joint_angular_limit_y_lower)
    bone_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, resource.joint_angular_limit_y_upper)

    bone_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, resource.joint_angular_limit_z_enabled)
    bone_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, resource.joint_angular_limit_z_lower)
    bone_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, resource.joint_angular_limit_z_upper)
    #endregion angular

    collider.shape = resource.collider_shape
    collider.position = resource.collider_offset
    collider.basis = resource.collider_rotation
