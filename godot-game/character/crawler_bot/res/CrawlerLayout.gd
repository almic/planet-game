@tool
class_name CrawlerLayout extends Resource

const META_OWNED: StringName = &'_crawler_layout'


@export_tool_button('Build Crawler', 'Bake')
var _btn_editor_build = editor_build_crawler


## Number of iteration loops used by the IK solver to produce more accurate results.
@export_range(0, 10, 1, 'or_greater')
var max_iterations: int = 4

## The target solve distance between the end bone and the target node.
## Iteration will only run while the distance is greater than this value.
@export_range(0.0, 1.0, 0.001, 'or_greater')
var min_distance: float = 0.001

## The total angular change allowed per second. This is divided evenly between
## each iteration relative to the current `Engine.physics_ticks_per_second`,
## unlike the Godot implementation which applies it per-iteration and doesn't
## consider frame rate or physics TPS.
@export_range(0.01, 180.0, 0.01, 'radians_as_degrees', 'suffix:°/s')
var angular_delta_limit: float = deg_to_rad(8.0)


## Generally, enabling this will copy the current skeleton pose and process that.
## When disabled, it is loaded once on the first run and never again.
@export var deterministic: bool = true

## Generally, this break limitations by treating the incoming rotation as the
## rest rotation. It should be turned off if the skeleton is modified by
## animations or other modifiers.
@export var mutable_bone_axes: bool = false


@export var leg_config_list: Array[CrawlerLegConfig]:
    set = set_leg_config_list


var crawler: CrawlerCharacter:
    set(value):
        crawler = value
        refresh_resources()


func editor_build_crawler() -> void:
    if not Engine.is_editor_hint():
        return

    if leg_config_list.size() < 1:
        EditorInterface.get_editor_toaster().push_toast(
                'This layout has no leg plan, there would be nothing to build.',
                EditorToaster.SEVERITY_ERROR
        )
        return

    if not crawler:
        EditorInterface.get_editor_toaster().push_toast(
                'No Crawler assigned, try reloading the scene.',
                EditorToaster.SEVERITY_ERROR
        )
        return

    if not crawler.skeleton:
        EditorInterface.get_editor_toaster().push_toast(
                'The Crawler has no assigned skeleton, set one and then try again.',
                EditorToaster.SEVERITY_ERROR
        )
        return

    var has_any_nodes_to_delete: bool = false
    for child in crawler.skeleton.get_children():
        if child.get_meta(META_OWNED, false):
            has_any_nodes_to_delete = true
            break

    var dialog := ConfirmationDialog.new()
    if has_any_nodes_to_delete:
        dialog.title = 'NODES WILL BE DELETED'
        dialog.dialog_text = (
                'Found an existing layout, which will be deleted prior to adding ' +
                'nodes to the current scene.\n' +
                'Please confirm'
        )
        dialog.confirmed.connect(
            func():
                clear_crawler()
                build_crawler()
        )
    else:
        dialog.dialog_text = 'This will add nodes to the current scene tree, please confirm'
        dialog.confirmed.connect(build_crawler)
    EditorInterface.popup_dialog_centered(dialog)


func refresh_resources() -> void:
    _refresh_leg_config_list()

func set_leg_config_list(new_config_list: Array[CrawlerLegConfig]) -> void:
    for old in leg_config_list:
        if not old:
            continue
        old.layout = null
    leg_config_list = new_config_list
    _refresh_leg_config_list()

func _refresh_leg_config_list() -> void:
    var index: int = -1
    for leg in leg_config_list:
        index += 1
        if not leg:
            continue
        leg.layout = self
        leg.layout_index = index

func get_bone_names() -> StringName:
    if (not crawler) or (not crawler.skeleton):
        return &''

    return crawler.skeleton.get_concatenated_bone_names()

func build_crawler() -> void:
    pass

func clear_crawler() -> void:
    var to_remove: Array[Node]
    for child in crawler.skeleton.get_children():
        if child.get_meta(META_OWNED, false):
            to_remove.append(child)

    for child in to_remove:
        crawler.skeleton.remove_child(child)
        child.queue_free()
