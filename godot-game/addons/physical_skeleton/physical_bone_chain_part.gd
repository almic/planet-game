@tool
class_name PhysicalBoneChainPart extends Resource


signal setting_changed(name: StringName)


## The bone this joint corresponds to, for editor convenience only.
@export_custom(
    PROPERTY_HINT_ENUM,
    '',
    PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
)
var bone_name: StringName

#region Physics
@export_group('Physics')

## Shape
@export var shape: Shape3D:
    set(value):
        shape = value
        setting_changed.emit(&'shape')

## Physics material
@export var physics_material: PhysicsMaterial:
    set(value):
        physics_material = value
        setting_changed.emit(&'physics_material')

## If continuous collision detection should be enabled
@export var continuous_cd: bool = true:
    set(value):
        continuous_cd = value
        setting_changed.emit(&'continuous_cd')

@export_subgroup('Collision', 'collision')
## Collision layer
@export_flags_3d_physics var collision_layer: int = 1:
    set(value):
        collision_layer = value
        setting_changed.emit(&'collision_layer')

## Collision mask
@export_flags_3d_physics var collision_mask: int = 1:
    set(value):
        collision_mask = value
        setting_changed.emit(&'collision_mask')
#endregion

#region IK Settings
@export_group('IK Settings')

## The total rest angle correction per second. This is applied one time just
## before starting the iteration loop, and is divided by the current
## `Engine.physics_ticks_per_second` so it is consistent with different TPS.
@export_range(0.0, 90.0, 0.1, 'radians_as_degrees', 'suffix:°/s')
var rest_correction_rate: float = deg_to_rad(45.0):
    set(value):
        rest_correction_rate = value
        setting_changed.emit(&'rest_correction_rate')

@export_subgroup('Rotation Axis', '')

## Allowed rotation axis for IK
@export_enum('X', 'Y', 'Z', 'All', 'Custom')
var rotation_axis: int = 3:
    set(value):
        rotation_axis = value
        setting_changed.emit(&'rotation_axis')

## Custom axis of rotation. Does not need to be normalized, the limitation will
## take a normalized copy for processing.
@export var custom_axis_vector: Vector3 = Vector3(1.0, 0.0, 0.0):
    set(value):
        custom_axis_vector = value
        setting_changed.emit(&'custom_axis_vector')


@export_subgroup('Limitation', 'limitation')

## Limitation resource, provides additional restrictions to limit the IK
@export var limitation_resource: JointLimitation3D:
    set(value):
        limitation_resource = value
        setting_changed.emit(&'limitation_resource')

@export_enum('None', '+X', '-X', '+Y', '-Y', '+Z', '-Z', 'Custom')
var limitation_right_axis: int = 0:
    set(value):
        limitation_right_axis = value
        setting_changed.emit(&'limitation_right_axis')

## Custom right axis of limitation. Does not need to be normalized, the
## limitation will take a normalized copy for processing.
@export var limitation_custom_right_axis_vector: Vector3:
    set(value):
        limitation_custom_right_axis_vector = value
        setting_changed.emit(&'limitation_custom_right_axis_vector')

## Rotation offset when applying limitation
@export var limitation_rotation_offset: Quaternion:
    set(value):
        limitation_rotation_offset = value
        setting_changed.emit(&'limitation_rotation_offset')
#endregion IK Settings

#region Motor Settings
@export_group('Motor Settings')

## If the motor should be enabled at run-time
@export var motor_enabled: bool = true

@export_subgroup('Torque Limit', 'torque')
## Torque drive limit when the joint is powered. Set to zero to simply disable
## the motor.
@export_range(0.0, 1000.0, 0.01, 'or_greater', 'hide_control', 'suffix:kg\u22C5m\u00B2/s\u00B2 (Nm)')
var torque_powered: float = 340282346638528859811704183484516925440.0:
    set(value):
        torque_powered = value
        setting_changed.emit(&'torque_powered')

## Torque drive limit when the joint is unpowered due to another joint in the
## chain being destroyed. Set to zero to simply disable the motor.
@export_range(0.0, 50.0, 0.01, 'or_greater', 'hide_control', 'suffix:kg\u22C5m\u00B2/s\u00B2 (Nm)')
var torque_unpowered: float = 10.0:
    set(value):
        torque_unpowered = value
        setting_changed.emit(&'torque_unpowered')
#endregion Motor Settings

#region Custom Joints
@export_group('Custom Joints', 'custom')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var custom_enabled: bool = false

## List of custom resources provided to the chain creation callback
@export var custom_joint_resource_list: Array[Resource]
#endregion Custom Joints
