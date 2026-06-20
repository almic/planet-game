@tool
extends EditorPlugin

func _enable_plugin() -> void:
    add_autoload_singleton('Signals', 'res://addons/await_any_all_signal/signals.gd')

func _disable_plugin() -> void:
    remove_autoload_singleton('Signals')

func _enter_tree():
    pass

func _exit_tree():
    pass
