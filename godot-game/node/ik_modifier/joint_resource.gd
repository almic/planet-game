extends Resource


enum RotationAxis {
    X = 0,
    Y = 1,
    Z = 2
}

enum RightAxis {
    None,
    POS_X,
    NEG_X,
    POS_Y,
    NEG_Y,
    POS_Z,
    NEG_Z,
}


@export_custom(
    PROPERTY_HINT_ENUM,
    '',
    PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
)
var bone_name: StringName

@export var rotation_axis: RotationAxis = RotationAxis.X

## Cone angle size of the limitation. The joint can effectively travel half this
## angle away from the rest position.
@export_range(0.0, 360.0, 0.01, 'radians_as_degrees')
var limitation_angle: float = deg_to_rad(90)

## Rotation offset from rest when applying limitation
@export var limitation_rotation_offset: Quaternion
