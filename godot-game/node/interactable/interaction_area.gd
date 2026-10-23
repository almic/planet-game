@tool
class_name InteractionArea extends Area3D


## The node this area is attached to
@export var interaction_object: Node3D

## If set to something other than none, InteractionRay must be aligned with
## this area's local axis in order to be considered for interaction. This can
## be used to prevent tunneling to higher priority areas intended to be used
## from a particular direction.
@export var required_direction: Direction = Direction.DIRECTION_NONE

## Minimum alignment angle of the InteractionRay, 90 degrees treats the direction
## as a plane, smaller than 90 degree angles require more precise positioning,
## and larger than 90 degree angles allow interaction from behind.
@export_range(0.1, 180.0, 0.1, 'radians_as_degrees')
var required_angle: float = PI * 0.5:
    set = set_angle

var _cos_required_angle: float


## Direction enum for ray matching, interaction area should be oriented so the
## desired axis is aligned with the direction of the interaction ray.
enum Direction {
    DIRECTION_NONE,

    DIRECTION_X_PLUS,
    DIRECTION_X_MINUS,

    DIRECTION_Y_PLUS,
    DIRECTION_Y_MINUS,

    DIRECTION_Z_PLUS,
    DIRECTION_Z_MINUS,
}


func _init() -> void:
    # NOTE: interaction area uses specific settings always

    # NOTE: this is only for interaction rays
    monitoring = false
    monitorable = false

    # NOTE: mask is pointless for interaction areas
    collision_mask = 0
    collision_priority = 1.0

    # NOTE: interaction area does none of these things
    input_ray_pickable = false
    input_capture_on_drag = false
    gravity_space_override = Area3D.SPACE_OVERRIDE_DISABLED
    linear_damp_space_override = Area3D.SPACE_OVERRIDE_DISABLED
    angular_damp_space_override = Area3D.SPACE_OVERRIDE_DISABLED
    wind_force_magnitude = 0.0
    wind_attenuation_factor = 0.0
    wind_source_path = NodePath()
    audio_bus_name = &""
    audio_bus_override = false
    reverb_bus_enabled = false
    reverb_bus_name = &""
    reverb_bus_amount = 0.0
    reverb_bus_uniformity = 0.0

    # force angle setting
    required_angle = required_angle

## Hide most properties from the editor to simplify configuration, as this
## node uses very specific settings that should not be changed
func _validate_property(property: Dictionary) -> void:
    const HIDDEN_PROPERTIES: PackedStringArray = [
        'collision_mask',
        'collision_priority',
        'input_ray_pickable',
        'input_capture_on_drag',
        'monitoring',
        'monitorable',
        'gravity_space_override',
        'linear_damp_space_override',
        'angular_damp_space_override',
        'wind_force_magnitude',
        'wind_attenuation_factor',
        'wind_source_path',
        'audio_bus_name',
        'audio_bus_override',
        'reverb_bus_enabled',
        'reverb_bus_name',
        'reverb_bus_amount',
        'reverb_bus_uniformity',
    ]

    if HIDDEN_PROPERTIES.has(property.name):
        property.usage &= ~PROPERTY_USAGE_EDITOR


func set_angle(value: float) -> void:
    required_angle = value
    _cos_required_angle = cos(required_angle)
