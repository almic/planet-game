@tool
class_name PhysicalBoneChain extends Resource


const BONE_NOT_FOUND: StringName = &'BONE NOT FOUND'


## Root bone of the IK chain
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, '')
var root_bone: StringName:
    set(value):
        root_bone = value
        _bone_list_dirty = true
        emit_changed()

## End bone of the IK chain
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, '')
var end_bone: StringName:
    set(value):
        end_bone = value
        _bone_list_dirty = true
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
        emit_changed()

## Custom unique identifier for this chain, generated the first time this chain
## is built in a scene. This is the hash of resource path and the bone names.
@export_custom(
    PROPERTY_HINT_NONE,
    '',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var unique_id: int = -1


var callable_get_bone_name: Callable
var callable_get_bone_name_hint: Callable:
    set(value):
        callable_get_bone_name_hint = value
        notify_property_list_changed()

var _bone_list: PackedInt32Array
var _bone_list_dirty: bool = true


func _validate_property(property: Dictionary) -> void:
    if property.name.ends_with('_bone'):
        if callable_get_bone_name_hint.is_valid():
            property.hint_string = callable_get_bone_name_hint.call()

func get_bone_list(skeleton: Skeleton3D = null) -> PackedInt32Array:
    if (not skeleton) and (not _bone_list_dirty):
        return _bone_list

    _bone_list.clear()

    if not skeleton:
        return _bone_list

    var bone_idx: int = skeleton.find_bone(end_bone)
    if bone_idx == -1:
        push_error(
            (
                'PhysicalBoneChain "%s" (at %s) is misconfigured. ' +
                'Failed to find bone id for end bone %s.'
            ) % [resource_name, resource_path, end_bone]
        )
        return _bone_list

    while true:
        # NOTE: skip the end bone, it should be a leaf which has no length
        bone_idx = skeleton.get_bone_parent(bone_idx)
        if bone_idx == -1:
            break

        _bone_list.append(bone_idx)
        var bone_name := StringName(skeleton.get_bone_name(bone_idx))
        if bone_name == root_bone:
            break

    if bone_idx == -1:
        push_error(
            (
                'PhysicalBoneChain "%s" (at %s) is misconfigured. ' +
                'Failed to find root bone %s as an ancestor of end bone %s.'
            ) % [resource_name, resource_path, root_bone, end_bone]
        )
        _bone_list.clear()
        return _bone_list

    _bone_list.reverse()
    _bone_list_dirty = false
    return _bone_list

func refresh_part_list_bone_names() -> void:
    var name_list: Array[StringName]

    if callable_get_bone_name.is_valid():
        for bone_idx in _bone_list:
            name_list.append(StringName(callable_get_bone_name.call(bone_idx)))

    var max_names: int = name_list.size()
    for index in range(part_list.size()):
        var part: PhysicalBoneChainPart = part_list[index]
        if not part:
            continue

        if index >= max_names:
            part.bone_name = BONE_NOT_FOUND
            continue

        part.bone_name = name_list[index]

func generate_unique_id() -> int:
    if not resource_path:
        push_error(
            (
                'PhysicalBoneChain named %s has not been saved yet, please ensure '
                + 'it has been saved and has a non-empty resource_path.'
            ) % resource_name
        )
        return -1

    if (not root_bone) or (not end_bone):
        push_error(
            (
                'PhysicalBoneChain %s (at %s) is missing a root and/or end bone. '
                + 'They must have both set before you can build the chain.'
            ) % [resource_name, resource_path]
        )
        return -1

    var hex: String = (resource_path + root_bone + end_bone).md5_text()
    unique_id = hex.substr(0, 16).hex_to_int() | 0x7FFFFFFFFFFFFFFF
    return unique_id
