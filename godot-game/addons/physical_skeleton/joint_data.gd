## Contains data and object references on a joint

## Related skeleton bone
var bone_idx: int = -1
## DEPRECATED: not used for anything, should probably be deleted
var bone_length: float = 0.0
## If this joint is part of an IK chain
var is_ik_joint: bool = false
## If this joint has a powered motor, disabled when IK chains are broken
var is_motor_powered: bool = true
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
