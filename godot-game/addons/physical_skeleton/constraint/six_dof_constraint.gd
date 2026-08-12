## Helper to estimate 6DOF constraint responses between two bodies.
## This is effectively an implementation of Jolt SixDOFConstraint.
extends RefCounted

const AngleConstraint = preload("uid://c3f0s01o84oa5")
const PointConstraint = preload("uid://du2yucfuswdp3")
const RotationConstraint = preload("uid://cq60q6r4f1d6k")

const Controller = preload("uid://bdhxyktjceoqv")

enum MotorState {
    Off,
    Velocity,
    PID,
}

## Position of constraint relative to parent center of mass
var _parent_local: Vector3
## Rotation which is the inverse of the relative constraint orientation
var _parent_constraint: Quaternion

## Position of constraint relative to body center of mass
var _body_local: Vector3
## Rotation which is the inverse of the relative constraint orientation
var _body_constraint: Quaternion
## Axes of constraint in world space, using body joint location
var _rotation_axis: Basis


var point_constraint: PointConstraint
var rotation_constraint: RotationConstraint
var motor_constraint: Array[AngleConstraint]
var motor_state: Array[MotorState]
var target_angular_velocity: Vector3
var torque_limit_min: Vector3
var torque_limit_max: Vector3


var target_angle: Vector3
var _motor_velocity_controller: Controller
var _motor_acceleration_controller: Controller


func _init(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        parent_constraint: Transform3D,
        body_constraint: Transform3D,
) -> void:
    _parent_local = parent_constraint.origin - parent.center_of_mass_local
    _parent_constraint = parent_constraint.basis.get_rotation_quaternion()

    _body_local = body_constraint.origin - body.center_of_mass_local
    _body_constraint = body_constraint.basis.get_rotation_quaternion()

    point_constraint = PointConstraint.new(_parent_local, _body_local)
    rotation_constraint = RotationConstraint.new()

    motor_constraint.resize(3)
    motor_state.resize(3)
    for i in range(3):
        motor_constraint[i] = AngleConstraint.new()
        motor_state[i] = MotorState.Off

    _motor_velocity_controller = Controller.new()
    _motor_acceleration_controller = Controller.new()

    _motor_velocity_controller.k_p = 16.0
    _motor_acceleration_controller.k_p = 2.0
    _motor_acceleration_controller.k_i = 1.0
    _motor_acceleration_controller.k_d = 2.0

## Set the rotation limits of the joint, in constraint-space.
func set_rotation_limit(limit_min: Vector3, limit_max: Vector3) -> void:
    rotation_constraint.set_limits(
        limit_min.x, limit_max.x,
        limit_min.y, limit_max.y,
        limit_min.z, limit_max.z,
    )

## Set the target angular joint velocity, in constraint-space.
func set_target_angular_velocity(target: Vector3) -> void:
    target_angular_velocity = target

func set_target_angle(target: Vector3) -> void:
    target_angle = target

## Set the motor torque limit by axis, in constraint-space. Typically you would
## pick a single value and let this be (-limit, +limit).
func set_torque_limit(limit_min: Vector3, limit_max: Vector3) -> void:
    torque_limit_min = limit_min
    torque_limit_max = limit_max

func load_lambda_from(joint: Generic6DOFJoint3D) -> void:
    point_constraint.set_total_lambda(joint.get_linear_lambda())

    var motor_lambda: Vector3 = joint.get_motor_angular_lambda()
    for i in range(3):
        motor_constraint[i].set_total_lambda(motor_lambda[i])

    rotation_constraint.set_total_lambda(joint.get_angular_lambda())

func setup(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> void:
    point_constraint.setup(parent, body)

    var constraint_parent: Quaternion = parent.transform.basis.get_rotation_quaternion() * _parent_constraint
    var constraint_body: Quaternion = body.transform.basis.get_rotation_quaternion() * _body_constraint
    var constraint_local: Quaternion = constraint_parent.inverse() * constraint_body

    rotation_constraint.setup(parent, body, constraint_local, constraint_parent)

    _rotation_axis = constraint_body
    for i in range(3):
        if motor_state[i] == MotorState.Velocity:
            motor_constraint[i].setup(parent, body, _rotation_axis[i], -target_angular_velocity[i])
        if motor_state[i] == MotorState.PID:
            # Put joint axis into body space
            var joint_axis: Vector3 = body.transform.basis.get_rotation_quaternion().inverse() * _rotation_axis[i]
            var rot: Quaternion = Quaternion(constraint_local * joint_axis, joint_axis) * constraint_local
            if rot.w < 0.0:
                rot = -rot
            var angle: float = rot.get_angle()
            if rot.get_axis().dot(joint_axis) < 0.0:
                angle = -angle
            target_angular_velocity[i] = -_motor_velocity_controller.compute(angle, target_angle[i], parent.step)
            motor_constraint[i].setup(parent, body, _rotation_axis[i])
        else:
            motor_constraint[i].deactivate()

func warm_start(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> void:
    for i in range(3):
        if motor_constraint[i].is_active():
            motor_constraint[i].warm_start(parent, body)

    rotation_constraint.warm_start(parent, body)
    point_constraint.warm_start(parent, body)

func solve_velocity(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        delta: float,
) -> bool:
    var impulse: bool = false
    var solve_impulse: bool

    var axis: Vector3
    var axis_velocity: float

    for i in range(3):
        if motor_constraint[i].is_active():
            if motor_state[i] == MotorState.Off:
                pass # I don't use friction state, I just set velocity to zero
            elif motor_state[i] == MotorState.Velocity:
                # NOTE: special difference, must update bias here.
                motor_constraint[i]._bias = -target_angular_velocity[i]
                axis = _rotation_axis[i]
                axis_velocity = -axis.dot(parent.angular_velocity - body.angular_velocity)
                solve_impulse = motor_constraint[i].solve_velocity(
                        parent,
                        body,
                        _rotation_axis[i],
                        delta * torque_limit_min[i],
                        delta * torque_limit_max[i]
                )
                axis_velocity = -axis.dot(parent.angular_velocity - body.angular_velocity)
                impulse = impulse || solve_impulse
            elif motor_state[i] == MotorState.PID:
                axis = _rotation_axis[i]
                var target_velocity: float = -target_angular_velocity[i]
                var current_velocity: float = _rotation_axis[i].dot(parent.angular_velocity - body.angular_velocity)
                var acceleration: float = _motor_acceleration_controller.compute(current_velocity, target_velocity, delta)
                motor_constraint[i]._bias = current_velocity + acceleration
                solve_impulse = motor_constraint[i].solve_velocity(
                        parent,
                        body,
                        _rotation_axis[i],
                        delta * torque_limit_min[i],
                        delta * torque_limit_max[i]
                )
                current_velocity = _rotation_axis[i].dot(parent.angular_velocity - body.angular_velocity)
                pass

    solve_impulse = rotation_constraint.solve_velocity(parent, body)
    impulse = impulse || solve_impulse

    axis_velocity = -axis.dot(parent.angular_velocity - body.angular_velocity)

    solve_impulse = point_constraint.solve_velocity(parent, body)
    impulse = impulse || solve_impulse

    axis_velocity = -axis.dot(parent.angular_velocity - body.angular_velocity)

    return impulse

func solve_position(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        baumgarte: float,
) -> bool:
    var impulse: bool = false
    var solve_impulse: bool

    var constraint_parent: Quaternion = parent.transform.basis.get_rotation_quaternion() * _parent_constraint
    var constraint_body: Quaternion = body.transform.basis.get_rotation_quaternion() * _body_constraint
    var constraint_local: Quaternion = constraint_parent.inverse() * constraint_body

    solve_impulse = rotation_constraint.solve_position(
            parent,
            body,
            constraint_local,
            _parent_constraint,
            _body_constraint,
            baumgarte
    )
    impulse = impulse || solve_impulse

    point_constraint.setup(parent, body)
    solve_impulse = point_constraint.solve_position(parent, body, baumgarte)
    impulse = impulse || solve_impulse

    return impulse
