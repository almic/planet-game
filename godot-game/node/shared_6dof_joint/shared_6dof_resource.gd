## The shared resource that connects Shared6DOFJoint nodes
@tool
class_name Shared6DOFResource extends Resource


## Shared nodes connect to this signal and simply call the "receive_update" method
signal shared_node_updated(res: Shared6DOFResource)


var _current_signal_node: Shared6DOFJoint
var _current_property: StringName
var _current_value: Variant
var _updating: bool = false
var _number_updated: int = 0


func send_update(caller_node: Shared6DOFJoint, property: StringName) -> void:
    if _updating:
        return

    _updating = true

    # print('Updating shared nodes from %s property "%s"' % [caller_node.name, property])
    _current_signal_node = caller_node
    _current_property = property

    _do_update.call_deferred()

func _do_update() -> void:
    _current_value = _current_signal_node.get(_current_property)
    _number_updated = 0
    shared_node_updated.emit(self)
    _updating = false

func receive_update(node: Shared6DOFJoint) -> void:
    if not _updating:
        push_error('Must not call receive_update outside of the `shared_node_updated` signal!')
        return

    # Ignore self updates
    if node == _current_signal_node:
        return

    # print('setting node %s property "%s" to value (%s)' % [node.name, _current_property, _current_value])
    node.set(_current_property, _current_value)
    _number_updated += 1

func last_updated_total() -> int:
    return _number_updated
