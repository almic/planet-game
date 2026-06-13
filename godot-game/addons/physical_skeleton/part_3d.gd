class_name PhysicalBonePart3D extends RigidBody3D


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

## The index of this part, corresponds to the index it was created with from a
## PhysicalBoneChainResource
@export_custom(
    PROPERTY_HINT_NONE,
    '',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var part_index: int


## The motor can no longer function due to damage and is in friction-only mode
var is_motor_broken: bool = false
## This part is powered, managed by the chain
var is_powered: bool = false
## This part can transfer power, determined by this part's health status
var is_power_interrupted: bool = true

## List of managed joints
var joint_list: Array[JointData]
## The single joint representing the bone this part is connected to
var bone_joint: JointData

## Cached center of mass, set before disabling the body, used by chain to assign
## the correct initial linear velocity when activating the body
var _cached_com: Vector3


func _ready() -> void:
    # TODO: load resource joints

    # TODO: load custom joints
    pass

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
    return []

## Creates joint nodes from the resource, connecting them to the parent_body if
## they are configured to do so.
func build_joints(
        chain: PhysicalBoneChain3D,
        main_body: RigidBody3D,
        parent_body: RigidBody3D,
        custom_joint_builder: Callable
) -> bool:
    # TODO: resource joints

    # Custom joints
    if (not resource.custom_enabled) or (not custom_joint_builder.is_valid()):
        return true

    for custom in resource.custom_joint_resource_list:
        var joint: Joint3D = custom_joint_builder.call(
            chain, self, main_body, parent_body, custom
        )

        if not joint:
            push_error(
                (
                    'PhysicalBonePart3D %s has custom joints defined, but the '
                    + 'builder failed to create a joint for the resource named '
                    + '%s (at %s). Either remove the custom joint resource, or '
                    + 'fix the cause of the builder failure.'
                ) % [name, custom.resource_name, custom.resource_path]
            )
            return false

        # TODO: place metadata on joint to remember it as custom
        # TODO: add to joint list

    return true

func update(skeleton: Skeleton3D, bone_idx: int) -> void:
    if not bone_joint.is_destroyed:
        _update_joint(bone_joint)

        var bone_rotation: Quaternion = skeleton.get_bone_rest(bone_idx).basis.get_rotation_quaternion() * bone_joint.offset.basis.get_rotation_quaternion()
        skeleton.set_bone_pose_rotation(bone_idx, bone_rotation)

        if bone_joint.is_breakable and _should_break(bone_joint.joint, bone_joint.offset):
            print('Breaking joint %s' % [bone_joint.joint.get_path()])
            is_motor_broken = true
            bone_joint.is_destroyed = true
            bone_joint.joint.queue_free()

    for i in range(1, joint_list.size()):
        var joint_data: JointData = joint_list[i]

        if joint_data.is_destroyed or (not joint_data.is_breakable):
            continue

        _update_joint(joint_data)

        if _should_break(joint_data.joint, joint_data.offset):
            print('Breaking joint %s' % [joint_data.joint.get_path()])
            joint_data.is_destroyed = true
            joint_data.joint.queue_free()

func _update_joint(joint_data: JointData) -> void:
    var parent_state := PhysicsServer3D.body_get_direct_state(joint_data.parent)
    var joint_parent: Transform3D = parent_state.transform * joint_data.xform_rel_parent
    var joint_body: Transform3D = global_transform * joint_data.xform_rel_body

    var body_diff: Transform3D = joint_parent.affine_inverse() * joint_body
    joint_data.offset = body_diff

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
        print('%d : %s: %.2f' % [Engine.get_physics_frames(), joint.name, total_force])
        # return true

    #print('error: %s\nangle: %s' % [displacement.origin, displacement.basis.get_euler()])

    return false

func setup_motor_velocity(skeleton: Skeleton3D, bone_idx: int) -> void:
    var target_rotation: Quaternion = skeleton.get_bone_pose_rotation(joint_data.bone_idx)
    target_rotation = skeleton.get_bone_rest(joint_data.bone_idx).basis.get_rotation_quaternion().inverse() * target_rotation

func solve_motor_velocity(delta: float) -> bool:

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
