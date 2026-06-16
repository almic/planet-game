@tool
class_name PhysicalBonePartResource extends Resource


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

@export_subgroup('Collision Shape', 'collider')
## Shape
@export var collider_shape: Shape3D:
    set(value):
        collider_shape = value
        setting_changed.emit(&'collider_shape')

## Shape translation offset, applied to the CollisionShape3D node
@export var collider_offset: Vector3:
    set(value):
        collider_offset = value
        setting_changed.emit(&'collider_offset')

## Shape rotation offset, applied to the CollisionShape3D node.
@export var collider_rotation: Quaternion:
    set(value):
        collider_rotation = value
        setting_changed.emit(&'collider_rotation')

@export_subgroup('Layers', 'collision')
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

#region Breakable
@export_group('Breakable', 'break')

## If this joint can be destroyed by excessive force. To use this on custom
## joints, you must apply the `PhysicalBonePart3D.META_BREAK_FORCE` meta data to
## the Joint3D created from the custom builder. This will act as the max break
## force value, using signals if `break_use_signal` is enabled.
@export var break_enabled: bool = false

## When enabled, the part will emit a signal when a joint's `break_max_force` is
## exceeded instead of instantly destroying the joint. Listeners must call the
## 'break()' method on the part if they wish the part to break during the signal.
@export var break_use_signal: bool = false

## The force at which the joint breaks, or the minimum force to emit the signal
## when `break_use_signal` is enabled. For custom Joint3D created from a custom
## builder, have the builder apply the `PhysicalBonePart3D.META_BREAK_FORCE`
## meta data to the Joint3D.
@export_range(1.0, 10000.0, 0.1, 'or_greater', 'suffix:N')
var break_max_force: float = 5000.0
#endregion Breakable

#region IK Settings
@export_group('IK Settings')

## If this part should create an IK setting
@export var ik_enabled: bool = false

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
        _update_joint_setting()

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
        if limitation_resource and limitation_resource.changed.is_connected(_update_joint_setting):
            limitation_resource.changed.disconnect(_update_joint_setting)
        limitation_resource = value
        if limitation_resource and (not limitation_resource.changed.is_connected(_update_joint_setting)):
            limitation_resource.changed.connect(_update_joint_setting)
        setting_changed.emit(&'limitation_resource')
        _update_joint_setting()

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
        _update_joint_setting()
#endregion IK Settings

#region Joint Settings
@export_group('Joint Settings')


## When enabled, will copy the angle from the IK limitation to the related angle
## limit on the joint. This will ONLY copy the angles, so any other setting will
## be retained.
@export var copy_ik_limitation_angle: bool = false:
    set(value):
        copy_ik_limitation_angle = value
        _update_joint_setting()

@export_subgroup('Linear Limit', 'joint_linear_limit')
@export var joint_linear_limit_x_enabled: bool = true:
    set(value):
        joint_linear_limit_x_enabled = value
        setting_changed.emit(&'joint_linear_limit_x_enabled')
@export_range(0.0, 1.0, 0.01, 'or_less', 'or_greater', 'hide_control', 'suffix:m')
var joint_linear_limit_x_upper: float = 0:
    set(value):
        joint_linear_limit_x_upper = value
        setting_changed.emit(&'joint_linear_limit_x_upper')
@export_range(0.0, 1.0, 0.01, 'or_less', 'or_greater', 'hide_control', 'suffix:m')
var joint_linear_limit_x_lower: float = 0:
    set(value):
        joint_linear_limit_x_lower = value
        setting_changed.emit(&'joint_linear_limit_x_lower')

@export var joint_linear_limit_y_enabled: bool = true:
    set(value):
        joint_linear_limit_y_enabled = value
        setting_changed.emit(&'joint_linear_limit_y_enabled')
@export_range(0.0, 1.0, 0.01, 'or_less', 'or_greater', 'hide_control', 'suffix:m')
var joint_linear_limit_y_upper: float = 0:
    set(value):
        joint_linear_limit_y_upper = value
        setting_changed.emit(&'joint_linear_limit_y_upper')
@export_range(0.0, 1.0, 0.01, 'or_less', 'or_greater', 'hide_control', 'suffix:m')
var joint_linear_limit_y_lower: float = 0:
    set(value):
        joint_linear_limit_y_lower = value
        setting_changed.emit(&'joint_linear_limit_y_lower')

@export var joint_linear_limit_z_enabled: bool = true:
    set(value):
        joint_linear_limit_z_enabled = value
        setting_changed.emit(&'joint_linear_limit_z_enabled')
@export_range(0.0, 1.0, 0.01, 'or_less', 'or_greater', 'hide_control', 'suffix:m')
var joint_linear_limit_z_upper: float = 0:
    set(value):
        joint_linear_limit_z_upper = value
        setting_changed.emit(&'joint_linear_limit_z_upper')
@export_range(0.0, 1.0, 0.01, 'or_less', 'or_greater', 'hide_control', 'suffix:m')
var joint_linear_limit_z_lower: float = 0:
    set(value):
        joint_linear_limit_z_lower = value
        setting_changed.emit(&'joint_linear_limit_z_lower')

@export_subgroup('Angular Limit', 'joint_angular_limit')
@export var joint_angular_limit_x_enabled: bool = true:
    set(value):
        joint_angular_limit_x_enabled = value
        setting_changed.emit(&'joint_angular_limit_x_enabled')
@export_range(-180.0, 180.0, 0.1, 'radians_as_degrees')
var joint_angular_limit_x_upper: float = 0:
    set(value):
        joint_angular_limit_x_upper = value
        setting_changed.emit(&'joint_angular_limit_x_upper')
@export_range(-180.0, 180.0, 0.1, 'radians_as_degrees')
var joint_angular_limit_x_lower: float = 0:
    set(value):
        joint_angular_limit_x_lower = value
        setting_changed.emit(&'joint_angular_limit_x_lower')

@export var joint_angular_limit_y_enabled: bool = true:
    set(value):
        joint_angular_limit_y_upper = value
        setting_changed.emit(&'joint_angular_limit_y_upper')
@export_range(-180.0, 180.0, 0.1, 'radians_as_degrees')
var joint_angular_limit_y_upper: float = 0:
    set(value):
        joint_angular_limit_y_upper = value
        setting_changed.emit(&'joint_angular_limit_y_upper')
@export_range(-180.0, 180.0, 0.1, 'radians_as_degrees')
var joint_angular_limit_y_lower: float = 0:
    set(value):
        joint_angular_limit_y_lower = value
        setting_changed.emit(&'joint_angular_limit_y_lower')

@export var joint_angular_limit_z_enabled: bool = true:
    set(value):
        joint_angular_limit_z_enabled = value
        setting_changed.emit(&'joint_angular_limit_z_enabled')
@export_range(-180.0, 180.0, 0.1, 'radians_as_degrees')
var joint_angular_limit_z_upper: float = 0:
    set(value):
        joint_angular_limit_z_upper = value
        setting_changed.emit(&'joint_angular_limit_z_upper')
@export_range(-180.0, 180.0, 0.1, 'radians_as_degrees')
var joint_angular_limit_z_lower: float = 0:
    set(value):
        joint_angular_limit_z_lower = value
        setting_changed.emit(&'joint_angular_limit_z_lower')
#endregion Joint Settings

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


## Updates copied joint setting from IK limitation
func _update_joint_setting() -> void:
    if not copy_ik_limitation_angle:
        return

    if rotation_axis > 2:
        return

    if not limitation_resource:
        return

    var limitation_angle: float = TAU
    var rotation_offset: Vector3 = Vector3.ZERO

    var limitation: JointLimitationCone3D = limitation_resource as JointLimitationCone3D
    if limitation:
        limitation_angle = limitation.angle
        rotation_offset = limitation_rotation_offset.get_euler()

        # Verify rotation offset is normal, should only apply on the axis of rotation
        for i in range(3):
            if i == rotation_axis:
                continue
            elif absf(rotation_offset[i]) >= 1.74e-3: # about 0.1 degrees
                var limit_axis_str: String
                if rotation_axis == 0:
                    limit_axis_str = 'X'
                elif rotation_axis == 1:
                    limit_axis_str = 'Y'
                else:
                    limit_axis_str = 'Z'

                var offset_axis_str: String
                if i == 0:
                    offset_axis_str = 'X'
                elif i == 1:
                    offset_axis_str = 'Y'
                else:
                    offset_axis_str = 'Z'
                push_error(
                    (
                        'PhysicalBoneChainPart %s (at %s) has misaligned limitation_rotation_offset. '
                        + 'Offsets should only be rotated on the axis they restrict, this limit acts '
                        + 'on the %s axis but contains rotation on the %s axis. Please correct the '
                        + 'rotation offset so that only axis %s has rotation.'
                    ) % [resource_name, resource_path, limit_axis_str, offset_axis_str, limit_axis_str]
                )
                return

    var lower_limit: float = rotation_offset[rotation_axis] - (limitation_angle * 0.5)
    var upper_limit: float = rotation_offset[rotation_axis] + (limitation_angle * 0.5)
    # NOTE: X and Z limits are way more likely than Y, so I check those first
    if rotation_axis == 0:
        joint_angular_limit_x_lower = lower_limit
        joint_angular_limit_x_upper = upper_limit
    elif rotation_axis == 2:
        joint_angular_limit_z_lower = lower_limit
        joint_angular_limit_z_upper = upper_limit
    else: # rotation_axis == 1
        joint_angular_limit_y_lower = lower_limit
        joint_angular_limit_y_upper = upper_limit
