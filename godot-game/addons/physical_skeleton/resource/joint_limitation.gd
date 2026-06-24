@tool
class_name IKJointLimitation extends Resource


## Cone angle size of the limitation. The joint can effectively travel half this
## angle away from the rest position.
@export_range(0.0, 360.0, 0.01, 'radians_as_degrees')
var angle: float = deg_to_rad(90):
    set(value):
        angle = value
        emit_changed()

## Rotation offset from rest when applying limitation
@export var rotation_offset: Quaternion:
    set(value):
        rotation_offset = value
        emit_changed()
