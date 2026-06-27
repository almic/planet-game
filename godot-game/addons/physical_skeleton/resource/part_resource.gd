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

#region Visual
@export_group('Visual')

## Mesh for a MeshInstance3D node
@export var mesh: Mesh:
    set(value):
        mesh = value
        setting_changed.emit(&'mesh')

## Translation offset for the mesh, applied to the MeshInstance3D node
@export var mesh_offset: Vector3:
    set(value):
        mesh_offset = value
        setting_changed.emit(&'mesh_offset')

## Rotation offset for the mesh, applied to the MeshInstance3D node
@export var mesh_rotation: Quaternion:
    set(value):
        mesh_rotation = value
        setting_changed.emit(&'mesh_rotation')

@export_subgroup('Bone Mesh', 'bone')
## If this part should create a new MeshInstance3D node to track the exact bone
## poses of the skeleton. Disabling will remove the created node.
@export var bone_enable_mesh: bool = false:
    set(value):
        bone_enable_mesh = value
        setting_changed.emit(&'bone_enable_mesh')

## Mesh override for the bone mesh. By default, the same mesh will be used.
@export var bone_mesh_override: Mesh = null:
    set(value):
        bone_mesh_override = value
        setting_changed.emit(&'bone_mesh_override')

## Material override for the bone mesh. Applied as the 'surface_material_override/0'
## to the bone MeshInstance3D
@export var bone_material_override: Material = null:
    set(value):
        bone_material_override = value
        setting_changed.emit(&'bone_material_override')
#endregion

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

## Allowed rotation axis for IK
@export_enum('X', 'Y', 'Z', 'None')
var rotation_axis: int = 3:
    set(value):
        rotation_axis = value
        setting_changed.emit(&'rotation_axis')
        _update_joint_setting()

## Limitation resource, provides additional restrictions to limit the IK
@export var limitation: IKJointLimitation:
    set(value):
        if limitation and limitation.changed.is_connected(_update_joint_setting):
            limitation.changed.disconnect(_update_joint_setting)
        limitation = value
        if limitation and (not limitation.changed.is_connected(_update_joint_setting)):
            limitation.changed.connect(_update_joint_setting)
        setting_changed.emit(&'limitation')
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

## Motor parameters
@export var motor_parameters: PhysicalMotorParameters:
    set(value):
        _disconnect_named(motor_parameters, &'motor_parameters')
        motor_parameters = value
        _connect_named_and_call(motor_parameters, &'motor_parameters')
#endregion Motor Settings

#region Custom Joints
@export_group('Custom Joints', 'custom')

@export var custom_enabled: bool = false

## List of custom resources provided to the chain creation callback
@export var custom_joint_resource_list: Array[Resource]
#endregion Custom Joints


func _connect_named_and_call(member: Resource, name: StringName) -> void:
    var binding: Callable = setting_changed.emit.bind(name)
    if member and (not member.changed.is_connected(binding)):
        member.changed.connect(binding)
    binding.call()

func _disconnect_named(member: Resource, name: StringName) -> void:
    var binding: Callable = setting_changed.emit.bind(name)
    if member and member.changed.is_connected(binding):
        member.changed.disconnect(binding)

## Updates copied joint setting from IK limitation
func _update_joint_setting() -> void:
    if not copy_ik_limitation_angle:
        return

    if rotation_axis > 2:
        return

    if not limitation:
        return

    var rotation_offset: Vector3 = limitation.rotation_offset.get_euler()

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

    var lower_limit: float = rotation_offset[rotation_axis] - (limitation.angle * 0.5)
    var upper_limit: float = rotation_offset[rotation_axis] + (limitation.angle * 0.5)
    # NOTE: X and Z limits are way more likely than Y, so I check those first
    #       Also, invert the angles because I'm pretty sure Godot are meth addicts
    if rotation_axis == 0:
        joint_angular_limit_x_lower = -upper_limit
        joint_angular_limit_x_upper = -lower_limit
    elif rotation_axis == 2:
        joint_angular_limit_z_lower = -upper_limit
        joint_angular_limit_z_upper = -lower_limit
    else: # rotation_axis == 1
        joint_angular_limit_y_lower = -upper_limit
        joint_angular_limit_y_upper = -lower_limit
