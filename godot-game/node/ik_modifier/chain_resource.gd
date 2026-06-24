@tool
extends Resource


const JointResource = preload("uid://c5ct6mxt0vyod")


signal bone_changed
signal joint_list_changed


## Root bone of this IK chain
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, '')
var root_bone: StringName:
    set(value):
        root_bone = value
        bone_changed.emit()

## End bone of this IK chain
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, '')
var end_bone: StringName:
    set(value):
        end_bone = value
        bone_changed.emit()

@export_custom(PROPERTY_HINT_NODE_PATH_VALID_TYPES, 'Node3D')
var target_node: NodePath

## Angle correction rate, helps bring the chain out of an awkward position by
## continuously bringing it back towards the rest pose angles
@export_range(0.0, 10.0, 0.01, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rest_correction: float = deg_to_rad(1.0)

@export var joint_list: Array[JointResource]:
    set(value):
        joint_list = value
        # Initialize any nulls
        for index in range(joint_list.size()):
            if joint_list[index] != null:
                continue
            joint_list[index] = JointResource.new()
            joint_list[index].resource_name = 'JointResource'
        joint_list_changed.emit()


var bone_name_hint: StringName:
    set(value):
        bone_name_hint = value
        notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
    if property.name.ends_with('_bone'):
        property.hint_string = bone_name_hint

func set_joint_count(count: int) -> void:
    var total: int = joint_list.size()
    if count == total:
        return
    joint_list.resize(count)
    joint_list = joint_list # Force setter call
