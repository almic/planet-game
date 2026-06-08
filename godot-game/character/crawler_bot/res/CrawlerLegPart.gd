@tool
class_name CrawlerLegPart extends Resource


## The bone this joint corresponds to, for convenience only
@export_custom(
    PROPERTY_HINT_ENUM,
    '',
    PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
)
var bone_name: StringName

#region Physics
@export_group('Physics')

## Shape
@export var shape: Shape3D

## Physics material
@export var physics_material: PhysicsMaterial

## If continuous collision detection should be enabled
@export var continuous_cd: bool = true

@export_subgroup('Collision', 'collision')
## Collision layer
@export_flags_3d_physics var collision_layer: int = 1

## Collision mask
@export_flags_3d_physics var collision_mask: int = 1
#endregion

#region IK Settings
@export_group('IK Settings')


@export_subgroup('Rotation Axis', '')

## Allowed rotation axis for IK
@export_enum('X', 'Y', 'Z', 'All', 'Custom')
var rotation_axis: int = 3

## Custom axis of rotation. Does not need to be normalized, the limitation will
## take a normalized copy for processing.
@export var custom_axis_vector: Vector3 = Vector3(1.0, 0.0, 0.0)


@export_subgroup('Limitation', 'limitation')

## Limitation resource, provides additional restrictions to limit the IK
@export var limitation_resource: JointLimitation3D = null

@export_enum('None', '+X', '-X', '+Y', '-Y', '+Z', '-Z', 'Custom')
var limitation_right_axis: int = 0

## Custom right axis of limitation. Does not need to be normalized, the
## limitation will take a normalized copy for processing.
@export var limitation_custom_right_axis_vector: Vector3

## Rotation offset when applying limitation
@export var limitation_rotation_offset: Quaternion
#endregion IK Settings

#region Motor Settings
@export_group('Motor Settings')

## If the motor should be enabled at run-time
@export var motor_enabled: bool = true

@export_subgroup('Torque Limit', 'torque')
## Torque drive limit when the joint is powered. Set to zero to simply disable
## the motor.
@export_range(0.0, 1000.0, 0.01, 'or_greater', 'hide_control', 'suffix:kg\u22C5m\u00B2/s\u00B2 (Nm)')
var torque_powered: float = 340282346638528859811704183484516925440.0

## Torque drive limit when the joint is unpowered due to another joint in the
## chain being destroyed. Set to zero to simply disable the motor.
@export_range(0.0, 50.0, 0.01, 'or_greater', 'hide_control', 'suffix:kg\u22C5m\u00B2/s\u00B2 (Nm)')
var torque_unpowered: float = 10.0
#endregion Motor Settings
