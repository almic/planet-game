## Uses shared resources to copy parameters to other Shared6DOFJoint nodes.
## Requires engine modifications of _set() virtual method to work.
@tool
class_name Shared6DOFJoint extends Generic6DOFJoint3D


@export var resource: Shared6DOFResource:
    set = set_resource

@export_tool_button('Share This to All', 'Signals')
@warning_ignore("unused_private_class_variable")
var _btn_editor_share_to_all = editor_share_to_all


var property_set: Dictionary = {}


func _ready() -> void:
    if not Engine.is_editor_hint():
        return

    var adding: bool = false
    for prop in get_property_list():
        if not adding:
            if prop.usage == PROPERTY_USAGE_CATEGORY and prop.name == 'Generic6DOFJoint3D':
                adding = true
            continue
        if prop.name == 'script':
            break
        if prop.usage == PROPERTY_USAGE_GROUP:
            continue
        property_set.set(prop.name, null)

    _connect_resource.call_deferred()

func _set(property: StringName, _value: Variant) -> bool:
    if Engine.is_editor_hint() and (property in property_set) and resource:
        resource.send_update(self, property)
    return false

func editor_share_to_all() -> void:
    if not resource:
        EditorInterface.get_editor_toaster().push_toast(
                'No resource set, there are no nodes to share to!',
                EditorToaster.SEVERITY_WARNING
        )
        return

    var dialog := ConfirmationDialog.new()
    dialog.dialog_text = 'This will overwrite all settings on any nodes connected to this one'
    dialog.confirmed.connect(
        func():
            share_to_all()
            EditorInterface.get_editor_toaster().push_toast(
                'Updated %d nodes using this shared resource!' % resource.last_updated_total(),
                EditorToaster.SEVERITY_INFO
            )
    )
    EditorInterface.popup_dialog_centered(dialog)

func share_to_all() -> void:
    if not resource:
        return

    for prop in property_set:
        resource.send_update(self, prop)

func on_updated(res: Shared6DOFResource) -> void:
    if res == resource:
         res.receive_update(self)

func set_resource(res: Shared6DOFResource) -> void:
    if resource and resource.shared_node_updated.is_connected(on_updated):
        resource.shared_node_updated.disconnect(on_updated)

    resource = res

    _check_resource()
    _connect_resource()

func _connect_resource() -> void:
    if (not resource) or resource.shared_node_updated.is_connected(on_updated):
        return
    resource.shared_node_updated.connect(on_updated)

func _check_resource() -> void:
    if not resource:
        return

    # Enforce this property
    resource.resource_local_to_scene = true

    # Push a warning when loading external resources
    if not resource.is_built_in():
        _push_warning.call_deferred(resource)

func _push_warning(res: Shared6DOFResource) -> void:
    var path: NodePath = get_path()
    var vp := get_viewport()

    if vp:
        path = vp.get_path_to(self)

    push_warning(
        (
            'Shared6DOFJoint at "%s" loaded an external Shared6DOFResource from %s. ' +
            'This is not supported, please use scene-loaded resources, do not save these to disk!'
        ) % [path, res.resource_path]
    )
