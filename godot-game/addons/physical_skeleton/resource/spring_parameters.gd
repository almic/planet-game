class_name PhysicalSpringParameters extends Resource


## If this spring should use frequency instead of a stiffness force
@export var use_frequency: bool = false

## Frequency of the spring, must set use_frequency to true
@export_range(0.0, 0.0, 0.01, 'or_greater', 'hide_control', 'suffix:Hz')
var frequency: float = 0.0

## Stiffness of the spring, must set use_frequency to false
@export_range(0.0, 0.0, 0.01, 'or_greater', 'hide_control', 'suffix:Nm')
var stiffness: float = 0.0

## Damping of the spring. When use_frequency is true, this represents a damping
## factor between 0 and 1. When use_frequency is false, this is a force value
## in Newton meters (Nm).
@export_range(0.0, 0.0, 0.01, 'or_greater', 'hide_control')
var damping: float = 0.0
