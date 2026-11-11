class_name LegGripSetting extends Resource


## Maximum force the gripper can apply, the constraint will break if it reaches
## this force
@export_range(0.0, 1000.0, 0.01, 'or_greater', 'suffix:N')
var max_force: float = 200.0

## Frequency of the spring
@export_range(0.0, 50.0, 0.01, 'or_greater', 'suffix:Hz')
var frequency: float = 10.0

## Damping of the spring
@export_range(0.0, 1.0, 0.01, 'or_greater')
var damping: float = 1.0

## When breaking, how long to wait before the gripper can re-apply
@export_range(0.01, 1.0, 0.01, 'or_greater', 'suffix:s')
var cooldown: float = 0.1
