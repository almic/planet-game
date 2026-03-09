@tool
extends EditorPlugin


func _enable_plugin() -> void:
    add_autoload_singleton("DebugDraw", "res://addons/debug_draw/draw_singleton.gd")


func _disable_plugin() -> void:
    remove_autoload_singleton("DebugDraw")


func _enter_tree() -> void:
    pass


func _exit_tree() -> void:
    pass
