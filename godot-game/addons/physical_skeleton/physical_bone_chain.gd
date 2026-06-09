@tool
class_name PhysicalBoneChain extends Resource


const BONE_NOT_FOUND: StringName = &'BONE NOT FOUND'


## Root bone of the IK chain
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, '')
var root_bone: StringName:
    set(value):
        root_bone = value
        _update_part_list()
        emit_changed()

## End bone of the IK chain
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, '')
var end_bone: StringName:
    set(value):
        end_bone = value
        _update_part_list()
        emit_changed()

## Part definitions for each segment of the chain
@export var part_list: Array[PhysicalBoneChainPart]:
    set(value):
        if part_list:
            for part in part_list:
                if (not part) or (not part.changed.is_connected(emit_changed)):
                    continue
                part.changed.disconnect(emit_changed)
        part_list = value
        if part_list:
            for part in part_list:
                if (not part) or part.changed.is_connected(emit_changed):
                    continue
                part.changed.connect(emit_changed)
        _update_part_list()
        emit_changed()


var skeleton: Skeleton3D


func _validate_property(property: Dictionary) -> void:
    if property.name.ends_with('_bone'):
        property.hint_string = skeleton.get_concatenated_bone_names()

func _update_part_list() -> void:
    var name_list: Array[StringName]
    var bone_idx: int = skeleton.find_bone(end_bone)
    if bone_idx == -1:
        push_error(
            (
                'PhysicalBoneChain "%s" (at %s) is misconfigured. ' +
                'Failed to find bone id for end bone %s.'
            ) % [resource_name, resource_path, end_bone]
        )
        return

    while true:
        # NOTE: skip the end bone, it should be a leaf which has no length
        bone_idx = skeleton.get_bone_parent(bone_idx)
        if bone_idx == -1:
            break

        var bone_name := StringName(skeleton.get_bone_name(bone_idx))
        name_list.append(bone_name)
        if bone_name == root_bone:
            break

    if bone_idx == -1:
        push_error(
            (
                'PhysicalBoneChain "%s" (at %s) is misconfigured. ' +
                'Failed to find root bone %s as an ancestor of end bone %s.'
            ) % [resource_name, resource_path, root_bone, end_bone]
        )
        return

    name_list.reverse()
    var max_names: int = name_list.size()
    for index in range(part_list.size()):
        var part: PhysicalBoneChainPart = part_list[index]
        if not part:
            continue

        if index >= max_names:
            part.bone_name = BONE_NOT_FOUND
            continue

        part.bone_name = name_list[index]
