## Helper for spring-like shape cast nodes
class_name SpringCast extends ShapeCast3D

## How much mass is supported by this spring. This value is used to make
## stiffness and damping mass-independant.
var mass: float = 1.0

## Offset from the shape cast's maximum extent
@export_range(-10.0, 10.0, 0.01, 'or_less', 'or_greater')
var height_offset: float = 0.0

@export_range(0.01, 2.0, 0.01, 'or_greater')
var stiffness: float = 2.5

@export_range(0.01, 1.0, 0.01, 'or_greater')
var damping: float = 2.2


var total_force: Vector3 = Vector3.ZERO

var direction: Vector3
var max_length: float

var length: float = INF
var last_length: float = INF
var normal: Vector3 = Vector3.ZERO


func _ready() -> void:
    update_spring()


## Call this when changing the direction or length of a spring
func update_spring() -> void:
    max_length = target_position.length()
    direction = -(target_position / max_length)
    last_length = INF

## Reads the current spring collision state and caches it
func save_state() -> void:
    if not is_colliding():
        length = INF
        normal = Vector3.ZERO
        return

    normal = get_collision_normal(0)
    length = get_closest_collision_safe_fraction() * max_length

## Calculates a spring force vector using the current state of the spring compared
## to its previous state. Accepts a bias to offset the spring rest length.
## Should only be called once per step.
func calculate_force(step: float, speed: float = INF, bias: float = 0.0, override_collision: bool = false) -> void:
    if override_collision or is_inf(length):
        last_length = INF
        total_force = Vector3.ZERO
        return

    var offset: float = length - (max_length + height_offset + bias)
    var cos_theta: float = clampf(normal.dot(direction), 0.0, 1.0)

    if is_inf(speed):
        if is_finite(last_length):
            speed = offset - last_length
        else:
            speed = offset
        speed /= step
    last_length = offset

    var spring: float = 100.0 * stiffness * -offset * mass
    var damp: float = 10.0 * damping * -speed * mass
    #print('%.4f | x: %.4f | s: %.4f | k: %.4f | c: %.4f | n: %.4f' % [float(Time.get_ticks_msec()) / 1000.0, offset, speed, spring, damp, cos_theta])

    total_force = clampf(spring + damp, 0.0, 1e8) * direction * cos_theta
    #print(total_force / mass)
