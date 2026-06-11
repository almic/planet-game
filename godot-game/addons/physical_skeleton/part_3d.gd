class_name PhysicalBonePart3D extends RigidBody3D


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


func _ready() -> void:
    pass

func update(skeleton: Skeleton3D, bone_idx: int) -> void:
    var to_remove: Array[JointData]
    for joint_data in joints:

        var joint_parent: Transform3D = joint_data.parent.global_transform * joint_data.xform_rel_parent
        var joint_body: Transform3D = joint_data.body.global_transform * joint_data.xform_rel_body

        var body_diff: Transform3D = joint_parent.affine_inverse() * joint_body
        joint_data.offset = body_diff

        if _should_break(joint_data.joint, joint_data.offset):
            to_remove.append(joint_data)

    _break_joints(to_remove)

    for joint_data in joints:
        if not joint_data.is_ik_joint:
            continue

        var bone_rotation: Quaternion = joint_data.offset.basis.get_rotation_quaternion()
        joint_data.angle = bone_rotation

        bone_rotation = skeleton.get_bone_rest(joint_data.bone_idx).basis.get_rotation_quaternion() * bone_rotation
        skeleton.set_bone_pose_rotation(joint_data.bone_idx, bone_rotation)

        # IDEA: Teleport IK end bone to real location? Maybe this will help IK

func _should_break(joint: Joint3D, displacement: Transform3D) -> bool:
    var total_force: float = 0
    if joint is BeamPivotJoint3D:
        total_force = joint.get_total_applied_force()
    elif joint is Generic6DOFJoint3D:
        var linear: float = joint.get_applied_force()
        var torque: float = joint.get_applied_torque()
        total_force = linear + torque

    if total_force > 500.0:
        print('%d : %s: %.2f' % [Engine.get_physics_frames(), joint.name, total_force])
        # return true

    #print('error: %s\nangle: %s' % [displacement.origin, displacement.basis.get_euler()])

    return false

func _break_joints(to_break: Array[JointData]) -> void:
    var to_disable: Array[RigidBody3D] = []

    for joint_data in to_break:
        print('Breaking joint %s on %s' % [joint_data.joint.name, main_body.name])

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
