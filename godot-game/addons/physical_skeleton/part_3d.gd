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
var is_power_interrupted: bool = false
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

## Physics State of the body, cached in update()
var body_state: PhysicsDirectBodyState3D
## Physics State of the parent, cached in update()
var parent_state: PhysicsDirectBodyState3D
## Angular velocity of the joint on the rotation axis, calculated in update()
var joint_velocity: float = 0.0
## Local axis index of the bone rotation
var bone_rotation_axis: int
## Calculated motor torque, used for constraints
var desired_motor_torque: float
## Internal velocity for spring-based joints, limits the rate of angle change
var spring_velocity: float = 0.0

## Calculated joint angle from IK
var _ik_angle: float
## Calculated angle delta from joint to IK target
var _ik_error: float
## Instant rate of change of this joint to the IK target
var ik_derivative: float
## Controller for ik angle
var _ik_controller: PIDController


#region Debug
var _debug_layer: CanvasLayer = null

@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false

## When true, this part will stop changing the joint motor velocity and spring
## angle, but otherwise do everything else
@export var debug_no_change: bool = false

const DEG_12: float = deg_to_rad(12.0)
const DEG_90: float = deg_to_rad(90.0)
const DEG_270: float = deg_to_rad(270.0)

var _debug_chart: DebugDraw.Chart = null

## Displays a graph showing angle measures
@export var debug_angle: bool = false
var _debug_angle_error_id: int = 0
const ANGLE_ERROR_RANGE: float = DEG_12
var _debug_joint_velocity_id: int = 0
const JOINT_VELOCITY_RANGE = DEG_270

## Displays a graph showing motor output
@export var debug_motor: bool = false
var _debug_motor_velocity_id: int = 0
const MOTOR_VELOCITY_RANGE: float = DEG_270
var _debug_motor_torque_id: int = 0
var _debug_motor_torque_ratio_id: int = 0

## Displays a graph showing spring output
@export var debug_spring: bool = false
var _debug_spring_target_id: int = 0
const SPRING_TARGET_RANGE: float = DEG_90
var _debug_spring_velocity_id: int = 0
const SPRING_VELOCITY_RANGE: float = DEG_270
#endregion Debug


func _ready() -> void:
    if _skip_ready:
        return

    _ik_controller = PIDController.new()

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
    main_joint.set_meta(&'_edit_lock_', true)
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
        if not mesh_bone_inst:
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
    body_state = PhysicsServer3D.body_get_direct_state(get_rid())
    parent_state = PhysicsServer3D.body_get_direct_state(bone_joint_data.parent)

    if not bone_joint_data.is_destroyed:
        _update_joint(bone_joint_data)

        skeleton.set_bone_global_pose(bone_idx, skeleton.global_transform.affine_inverse() * body_state.transform)

        if bone_joint_data.is_breakable and _should_break(bone_joint_data.joint, bone_joint_data.offset):
            #print('Breaking joint %s' % [get_nice_path(bone_joint)])
            is_motor_broken = true
            is_motor_powered = false
            bone_joint_data.is_destroyed = true
            bone_joint.queue_free()
            bone_joint = null
            bone_joint_data.joint = null

        if bone_joint:
            _update_motor_state()

        is_using_power = is_motor_powered

    # NOTE: update other custom joints, skip the first which is the main bone_joint_data
    for i in range(1, joint_data_list.size()):
        var joint_data: JointData = joint_data_list[i]

        if joint_data.is_destroyed or (not joint_data.is_breakable):
            continue

        _update_joint(joint_data)

        if _should_break(joint_data.joint, joint_data.offset):
            #print('Breaking joint %s' % [get_nice_path(joint_data.joint)])
            joint_data.is_destroyed = true
            joint_data.joint.queue_free()
            joint_data.joint = null

    if _debug_layer:
        _debug_layer.visible = debug_enable

    if _debug_chart:
        _debug_chart.visible = debug_enable and (debug_motor or debug_angle)
    elif debug_enable:
        _setup_debug_chart()

func _update_joint(joint_data: JointData) -> void:
    var joint_parent_state := PhysicsServer3D.body_get_direct_state(joint_data.parent)
    var joint_parent: Transform3D = joint_parent_state.transform * joint_data.xform_rel_parent
    var joint_body: Transform3D = body_state.transform * joint_data.xform_rel_body

    var body_diff: Transform3D = joint_parent.affine_inverse() * joint_body
    joint_data.offset = body_diff

func _update_motor_state() -> void:
    var motor_should_be_powered: bool = is_powered and (not is_motor_broken)
    var powered_changed: bool = is_motor_powered != motor_should_be_powered
    is_motor_powered = motor_should_be_powered

    # Setting only the limitation axis
    if not resource.ik_enabled:
        return

    var motor_axis: int = resource.rotation_axis
    if motor_axis < 0 or motor_axis > 2:
        push_error(
            (
                'PhysicalBonePart3D at %s has a motor with an invalid rotation '
                + 'axis. Rotation axes for joints must be set to 0-2.'
            ) % get_nice_path()
        )
        return

    for axis in range(3):
        var has_motor: bool = bone_joint.get_flag(axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR)
        var has_spring: bool = bone_joint.get_flag(axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)

        if axis != motor_axis:
            if has_motor:
                bone_joint.set_flag(axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
                bone_joint.set_flag(axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR_PID_ACCELERATION_ANGULAR, false)
            if has_spring:
                bone_joint.set_flag(axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
        else:
            if has_motor != resource.motor_enabled:
                bone_joint.set_flag(axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, resource.motor_enabled)
            if has_spring != resource.spring_enabled:
                bone_joint.set_flag(motor_axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, resource.spring_enabled)
            if powered_changed:
                bone_joint.set_flag(motor_axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR_PID_ACCELERATION_ANGULAR, is_motor_powered)

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

    return false

func set_should_break() -> void:
    _signal_should_break = true

func on_pose_finalized(bone_xform: Transform3D, bone_rest: Quaternion) -> void:
    _ensure_mesh_bone_inst()
    if mesh_bone_inst:
        mesh_bone_inst.global_transform = bone_xform.translated_local(resource.mesh_offset)

    var axis: int = resource.rotation_axis
    if axis < 0 or axis > 2:
        push_error(
            (
                'PhysicalBonePart3D at %s has a motor with an invalid rotation '
                + 'axis. Rotation axes for joints must be set to 0-2.'
            ) % get_nice_path()
        )
        return

    bone_rotation_axis = axis

    var part_velocity: Vector3 = body_state.angular_velocity
    var parent_velocity: Vector3 = parent_state.angular_velocity
    var rotation_axis: Vector3 = (body_state.transform.basis * bone_joint_data.xform_rel_body.basis)[bone_rotation_axis]
    joint_velocity = rotation_axis.dot(parent_velocity - part_velocity)

    if debug_enable and debug_angle and _debug_chart:
        _debug_chart.insert(_debug_joint_velocity_id, joint_velocity)

    var pose: Quaternion = bone_xform.basis

    # Relative to rest
    pose = (bone_rest.inverse() * pose).normalized()

    # Axis correction
    var local_axis: Vector3 = Vector3.ZERO
    local_axis[bone_rotation_axis] = 1.0
    pose = (Quaternion(pose * local_axis, local_axis) * pose).normalized()

    if pose.w < 0.0:
        pose = -pose

    _ik_angle = pose.get_angle()
    if pose.get_axis().dot(local_axis) < 0:
        _ik_angle = -_ik_angle

    # Error calculation with axis correction
    var rot: Quaternion = bone_joint_data.offset.basis.get_rotation_quaternion()
    rot = (Quaternion(rot * local_axis, local_axis) * rot).normalized()
    var angle: float = rot.get_angle()
    if rot.get_axis().dot(local_axis) < 0.0:
        angle = -angle
    _ik_error = _ik_angle - angle

    if debug_enable and debug_angle and _debug_chart:
        var angle_error: float = clampf(_ik_error, -100.0, 100.0)
        _debug_chart.insert(_debug_angle_error_id, angle_error)

func apply_motor_parameters() -> void:
    if resource.motor_enabled:
        _update_motor()

    if resource.spring_enabled:
        _update_spring()

func _update_motor() -> void:
    var angle_error: float = _remap_target(
            _ik_error,
            resource.motor_parameters.control_angle_threshold,
            resource.motor_parameters.control_angle_range
    )

    _ik_controller.update_parameters(resource.motor_parameters.angle_controller)
    var target_velocity: float = _ik_controller.update(angle_error, 0.0, body_state.step)

    target_velocity = _remap_target(
            target_velocity,
            resource.motor_parameters.control_velocity_threshold,
            resource.motor_parameters.control_velocity_range
    )

    # Scale target velocity by ik derivative, including directional inversion
    if absf(_ik_error) > 1.74e-4:
        target_velocity *= clampf(ik_derivative / _ik_error, -1.0, 1.0)

    var max_accel: float = resource.motor_parameters.max_acceleration * body_state.step

    if signf(target_velocity) == signf(joint_velocity):
        if absf(target_velocity) > absf(joint_velocity):
            target_velocity = move_toward(joint_velocity, target_velocity, max_accel)
    else:
        target_velocity = move_toward(0.0, target_velocity, maxf(0.0, max_accel - absf(joint_velocity)))

    # NOTE: limit max velocity by actual error, not the remapped error
    var max_velocity: float = minf(absf(_ik_error) / body_state.step, resource.motor_parameters.max_velocity)
    target_velocity = signf(target_velocity) * minf(absf(target_velocity), max_velocity)

    if debug_enable and debug_motor and _debug_chart:
        _debug_chart.insert(_debug_motor_velocity_id, target_velocity)

    var new_velocity: Vector3 = Vector3.ZERO
    new_velocity[bone_rotation_axis] = target_velocity

    if debug_enable and debug_no_change:
        pass
    else:
        bone_joint.set_angular_target_velocity(new_velocity)

    var motor_axis: Generic6DOFJoint3D.MotorAxis = Generic6DOFJoint3D.MOTOR_AXIS_ANGULAR + bone_rotation_axis
    var param: PhysicalControllerParameters = resource.motor_parameters.motor_controller
    bone_joint.set_motor_pid_acceleration(motor_axis, param.proportional, param.integral, param.derivative)

    desired_motor_torque = _calculate_torque(joint_velocity)

    if bone_rotation_axis == 0:
        bone_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, desired_motor_torque)
    elif bone_rotation_axis == 2:
        bone_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, desired_motor_torque)
    else:
        bone_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_DRIVE_TORQUE_LIMIT, desired_motor_torque)

    if debug_enable and debug_motor and _debug_chart:
        var torque_ratio: float = desired_motor_torque / resource.motor_parameters.torque_powered_max
        _debug_chart.insert(_debug_motor_torque_ratio_id, torque_ratio)
        var torque_applied: float = absf(bone_joint.get_applied_torque()) / resource.motor_parameters.torque_powered_max
        _debug_chart.insert(_debug_motor_torque_id, torque_applied)

func _update_spring() -> void:
    var equilibrium: Vector3 = bone_joint.get_angular_spring_target()
    var target: Vector3 = Vector3.ZERO
    target[bone_rotation_axis] = -_ik_angle

    # Accelerate in direction of change
    var error: float = target[bone_rotation_axis] - equilibrium[bone_rotation_axis]
    var part_velocity: Vector3 = body_state.angular_velocity
    var parent_velocity: Vector3 = parent_state.angular_velocity

    var max_velocity: float = resource.motor_parameters.max_velocity
    var acceleration: float = resource.motor_parameters.max_acceleration * body_state.step
    if joint_velocity != 0.0 and signf(error) != signf(joint_velocity):
        spring_velocity = 0.0
    else:
        # Match joint velocity with some acceleration window
        spring_velocity = joint_velocity + clampf(spring_velocity - joint_velocity, -acceleration, acceleration)

    spring_velocity += signf(error) * acceleration
    spring_velocity = clampf(spring_velocity, -max_velocity, max_velocity)

    equilibrium = equilibrium.move_toward(target, minf(absf(spring_velocity * body_state.step), absf(error)))

    if debug_enable and debug_spring and _debug_chart:
        _debug_chart.insert(_debug_spring_target_id, equilibrium[bone_rotation_axis])
        _debug_chart.insert(_debug_spring_velocity_id, spring_velocity)

    if debug_enable and debug_no_change:
        pass
    else:
        bone_joint.set_angular_spring_target(equilibrium)

    bone_joint.set_param(
        bone_rotation_axis,
        Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS,
        resource.spring_parameters.stiffness
    )

    bone_joint.set_param(
        bone_rotation_axis,
        Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING,
        resource.spring_parameters.damping
    )

    var rid: RID = bone_joint.get_rid()

    JoltPhysicsServer3D.generic_6dof_joint_set_jolt_flag(
        rid, bone_rotation_axis,
        JoltPhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_ANGULAR_SPRING_FREQUENCY,
        resource.spring_parameters.use_frequency
    )

    JoltPhysicsServer3D.generic_6dof_joint_set_jolt_param(
        rid, bone_rotation_axis,
        JoltPhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_FREQUENCY,
        resource.spring_parameters.frequency
    )

## IK Angle interpolation
func _remap_target(value: float, threshold: float, window: float) -> float:
    if window < 1e-6:
        if absf(value) >= threshold:
            return value
        else:
            return 0.0
    var x: float = clampf((absf(value) - threshold) / window, 0.0, 1.0)
    return value * (x * x * x * (x * (6.0 * x - 15.0) + 10.0))

## Torque interpolation curve
func _calculate_torque(velocity: float) -> float:
    var velocity_ratio: float = absf(velocity) / resource.motor_parameters.max_velocity
    return resource.motor_parameters.torque_powered_max * clampf(1.0 - pow(
            velocity_ratio / (1.0 + resource.motor_parameters.torque_zero_speed),
            1.0 / resource.motor_parameters.torque_curve
    ), 0.0, 1.0)

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

    collider.shape = resource.collider_shape
    collider.position = resource.collider_offset
    collider.basis = resource.collider_rotation

    # Could have been destroyed
    if not bone_joint:
        return

    if resource.break_enabled:
        bone_joint.set_meta(META_BREAK_FORCE, resource.break_max_force)
    else:
        bone_joint.remove_meta(META_BREAK_FORCE)

    # GODOT PLEASE
    #region linear
    bone_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, resource.joint_linear_limit_x_enabled)
    bone_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, resource.joint_linear_limit_y_enabled)
    bone_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, resource.joint_linear_limit_z_enabled)

    bone_joint.set_linear_limit(
            Vector3(
                resource.joint_linear_limit_x_lower,
                resource.joint_linear_limit_y_lower,
                resource.joint_linear_limit_z_lower
            ),
            Vector3(
                resource.joint_linear_limit_x_upper,
                resource.joint_linear_limit_y_upper,
                resource.joint_linear_limit_z_upper
            )
    )
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

func _setup_debug_chart() -> void:
    _debug_chart = DebugDraw.Chart.new()
    _debug_chart.name = name

    _debug_angle_error_id = _debug_chart.create_series(
            "Angle Error",
            Vector4(INF, INF, -ANGLE_ERROR_RANGE, ANGLE_ERROR_RANGE)
    )

    _debug_joint_velocity_id = _debug_chart.create_series(
            "Joint Velocity",
            Vector4(INF, INF, -MOTOR_VELOCITY_RANGE, MOTOR_VELOCITY_RANGE)
    )

    _debug_motor_velocity_id = _debug_chart.create_series(
            "Motor Velocity",
            Vector4(INF, INF, -MOTOR_VELOCITY_RANGE, MOTOR_VELOCITY_RANGE)
    )

    _debug_motor_torque_id = _debug_chart.create_series(
            "Applied Torque",
            Vector4(INF, INF, -0.2, 1.2)
    )

    _debug_motor_torque_ratio_id = _debug_chart.create_series(
            "Torque Ratio",
            Vector4(INF, INF, -0.2, 1.2)
    )

    _debug_spring_target_id = _debug_chart.create_series(
            "Spring Equilibrium",
            Vector4(INF, INF, -SPRING_TARGET_RANGE, SPRING_TARGET_RANGE)
    )

    _debug_spring_velocity_id = _debug_chart.create_series(
            "Spring Velocity",
            Vector4(INF, INF, -SPRING_VELOCITY_RANGE, SPRING_VELOCITY_RANGE)
    )

    for chart_id in [
            _debug_angle_error_id,
            _debug_joint_velocity_id,
            _debug_motor_velocity_id,
            _debug_motor_torque_id,
            _debug_motor_torque_ratio_id,
            _debug_spring_target_id,
            _debug_spring_velocity_id,
    ]:
        _debug_chart.set_data_limit(chart_id, 100)

    # NOTE: the displayed velocity is technically last frame's velocity, so add
    # a zero point to motor velocity to shift it up
    _debug_chart.insert(_debug_motor_velocity_id, 0.0)

    if not _debug_layer:
        _debug_layer = DebugDraw.get_layer(&'physical_bone_part_debug')

    var chart_grid: GridContainer = _debug_layer.find_child(&'chart_grid', false, false) as GridContainer
    if not chart_grid:
        chart_grid = GridContainer.new()
        chart_grid.name = &'chart_grid'
        chart_grid.anchor_bottom = 1.0
        chart_grid.anchor_right = 1.0
        chart_grid.columns = 1
        _debug_layer.add_child(chart_grid, true)

    chart_grid.add_child(_debug_chart, true)
