## Helper to estimate 6DOF constraint responses between two bodies.
## This is effectively an implementation of Jolt SixDOFConstraint.
extends RefCounted

const PointConstraint = preload("uid://du2yucfuswdp3")
const RotationConstraint = preload("uid://cq60q6r4f1d6k")

## Position of constraint relative to parent center of mass
var _parent_local: Vector3
## Rotation which is the inverse of the relative constraint orientation
var _parent_constraint: Quaternion

## Position of constraint relative to body center of mass
var _body_local: Vector3
## Rotation which is the inverse of the relative constraint orientation
var _body_constraint: Quaternion


var point_constraint: PointConstraint
var rotation_constraint: RotationConstraint



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

func setup(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> void:
    point_constraint.setup(parent, body)

    var constraint_parent: Quaternion = parent.transform.basis.get_rotation_quaternion() * _parent_constraint
    var constraint_body: Quaternion = body.transform.basis.get_rotation_quaternion() * _body_constraint
    var constraint_local: Quaternion = constraint_parent.inverse() * constraint_body

    rotation_constraint.setup(parent, body, constraint_local, constraint_parent)
