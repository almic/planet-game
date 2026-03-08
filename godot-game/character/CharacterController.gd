class_name CharacterController extends RigidBody3D


@export_group('Movement')

## Acceleration rate in the desired direction. Set this to zero to always move
## at max_speed.
@export_range(0.0, 3.0, 0.01, 'or_greater')
var acceleration: float = 1.0

## Maximum speed, will stop accelerating from input when this speed is reached.
## Set to zero to have no limit, requires acceleration to be positive, otherwise
## 1.0 is used as the max speed.
@export_range(0.0, 10.0, 0.01, 'or_greater')
var max_speed: float = 5.0

## Stopping rate when controller should not move. Set to zero to disable stopping.
@export_range(0.0, 20.0, 0.01, 'or_greater')
var deceleration: float = 8.0


@export_group('Floor Collision')

## Shape cast to use for colliding with the ground, like a spring. Set up the
## shape cast such that its extent is equal to the step-down height.
@export var shape_cast: ShapeCast3D

## Offset from the shape cast's maximum extent, use this to subtract the step-down
## height added.
@export_range(-10.0, 10.0, 0.01, 'or_less', 'or_greater')
var height_offset: float = 0.0

@export var spring_stiffness: float = 1.0

@export var spring_damping: float = 2.0



var is_on_floor: bool = false

var desired_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
    # At least 1 result is needed for ground slope detection
    if shape_cast.max_results == 0:
        shape_cast.max_results = 1

## Implement per controller, called when input should be read for movement.
## If your controller has a camera connect to mouse movement, you should handle
## that directly in _process() instead.
func _handle_input() -> void:
    pass


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:

    _handle_input()

    if not shape_cast.is_colliding():
        if is_on_floor:
            is_on_floor = false
        return

    if not is_on_floor:
        is_on_floor = true

    if desired_velocity.is_zero_approx():
        linear_velocity -= linear_velocity * deceleration * state.step
    else:
        linear_velocity = linear_velocity * 0.75 + desired_velocity * 0.25

    var max_length: float = shape_cast.target_position.length()
    var spring_direction: Vector3 = -(shape_cast.target_position / max_length)
    var length: float = shape_cast.get_closest_collision_safe_fraction() * max_length
    var normal: Vector3 = shape_cast.get_collision_normal(0)

    var up_velocity: float = spring_direction.dot(state.linear_velocity)

    var offset: float = max_length - length - height_offset
    var spring: float = 100.0 * spring_stiffness * offset
    var damp: float = minf(10.0 * spring_damping * up_velocity, spring)

    var push: Vector3 = (
            clampf(spring - damp, 0.0, 1e8) * mass
            * spring_direction * clampf(normal.dot(spring_direction), 0.5, 1.0)
        )
    state.apply_central_force(push)
