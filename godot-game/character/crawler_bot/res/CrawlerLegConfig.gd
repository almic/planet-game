@tool
class_name CrawlerLegConfig extends Resource


const BONE_NOT_FOUND: StringName = &'BONE NOT FOUND'


@export_custom(PROPERTY_HINT_ENUM, '')
var root_bone: StringName:
    set(value):
        root_bone = value
        _update_part_list()

@export_custom(PROPERTY_HINT_ENUM, '')
var end_bone: StringName:
    set(value):
        end_bone = value
        _update_part_list()

@export var part_list: Array[CrawlerLegPart]:
    set(value):
        part_list = value
        _update_part_list()

@export var leg_setting: CrawlerLegSetting

var layout: CrawlerLayout:
    set(value):
        layout = value
        _refresh()
var layout_index: int = -1


func _validate_property(property: Dictionary) -> void:
    if not layout:
        return

    if property.name.ends_with('_bone'):
        property.hint_string = layout.get_bone_names()

func _refresh() -> void:
    _update_part_list()

func _update_part_list() -> void:
    var skeleton: Skeleton3D = layout.crawler.skeleton

    var name_list: Array[StringName]
    var bone_idx: int = skeleton.find_bone(end_bone)
    if bone_idx == -1:
        push_error(
            (
                'Leg Layout at index %d of %s (%s) has a misconfigured bone chain. ' +
                'Failed to find bone id for end bone %s.'
            ) % [layout_index, layout.resource_name, layout.resource_path, end_bone]
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
                'Leg Layout at index %d of %s (%s) has a misconfigured bone chain. ' +
                'Failed to find root bone %s as an ancestor of end bone %s.'
            ) % [layout_index, layout.resource_name, layout.resource_path, root_bone, end_bone]
        )
        return

    name_list.reverse()
    var max_names: int = name_list.size()
    for index in range(part_list.size()):
        var part: CrawlerLegPart = part_list[index]
        if not part:
            continue

        if index >= max_names:
            part.bone_name = BONE_NOT_FOUND
            continue

        part.bone_name = name_list[index]
