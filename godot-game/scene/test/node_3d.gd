@tool
extends Node3D


func _ready() -> void:
    set_notify_transform(true)

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSFORM_CHANGED:
        var rot: Quaternion = basis.get_rotation_quaternion()
        print('angle: %.2f' % rad_to_deg(rot.get_angle()))
        print('axis:  %s' % rot.get_axis())
