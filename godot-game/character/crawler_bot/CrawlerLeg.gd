@tool
class_name CrawlerLeg extends Node3D

@export var shape_cast: ShapeCast3D
@export var target: Marker3D

## How far between current and next step position to start moving the leg
@export_range(0.01, 1.0, 0.01, 'or_greater')
var step_distance: float = 0.7

## How much to lift the leg while taking a step, applies on the body's up axis
@export_range(0.0, 1.0, 0.01, 'or_greater')
var leg_lift_height: float = 0.5

## How much to swing the leg out while taking a step, applies on the body's right axis
@export_range(0.0, 1.0, 0.01, 'or_greater')
var leg_swing_offset: float = 0.2

## When in motion, how far in the direction of travel to shift the leg
@export_range(0.0, 1.0, 0.01, 'or_greater')
var move_offset: float = 0.6

## When in motion, how far in the direction of travel to rotate the leg. For
## front and back legs, the leg only rotates forward or backward, respectively.
@export_range(0.0, 45.0, 0.1, 'radians_as_degrees')
var move_spin: float = deg_to_rad(15.0)

## How quickly to interpolate in/out of leg move offsets.
@export_range(1.0, 10.0, 0.01, 'or_greater')
var move_interp_rate: float = 8.0


var body: CrawlerCharacter = null
var index: int = -1

## Transform of the leg root when at rest, set when the body enters the scene
var rest_transform: Transform3D

var is_grounded: bool = false
var is_moving: bool = false

var next_step_target: Vector3
var step_target: Vector3

var step_current: Vector3
var step_delta: float

var shape_rid: RID


func _ready() -> void:
    if not shape_cast:
        for child in find_children('', 'ShapeCast3D', false):
            shape_cast = child as ShapeCast3D
            if shape_cast:
                break
    if not target:
        for child in find_children('', 'Marker3D', false):
            target = child as Marker3D
            if target:
                break

    rest_transform = transform

    # Ensure target is top-level in-game
    target.top_level = not Engine.is_editor_hint()
    next_step_target = target.global_position

func update(state: PhysicsDirectBodyState3D) -> void:

    var is_left: bool = index % 2 == 0

    var target_transform: Transform3D = rest_transform
    var travel_speed: float
    var travel_forward: Vector3
    if not body.ground_direction.is_zero_approx():
        travel_speed = minf(maxf(body.ground_direction.dot(body.ground_velocity), body.desired_speed), body.max_speed)
        if body.desired_direction.is_zero_approx():
            travel_forward = body.ground_direction
        else:
            travel_forward = body.desired_direction
        travel_forward = travel_forward.slide(state.transform.basis.y)
        if not travel_forward.is_zero_approx():
            travel_forward = travel_forward.normalized()

    if not travel_forward.is_zero_approx():
        target_transform.origin += state.transform.basis.inverse() * travel_forward * move_offset

        var is_front: bool = index < 2
        var is_back: bool = index + 2 >= body.legs.size()

        var cos_theta: float = travel_forward.dot(-state.transform.basis.z)

        if is_front or is_back:
            cos_theta = absf(cos_theta) * 2.0 - 1.0
            if is_front:
                if is_left:
                    cos_theta *= -1.0
            elif not is_left:
                cos_theta *= -1.0
        elif is_left:
            cos_theta *= -1.0

        target_transform = target_transform.rotated_local(transform.basis.y, move_spin * cos_theta)

    if transform != target_transform:
        transform = transform.interpolate_with(target_transform, state.step * move_interp_rate)
        if transform.is_equal_approx(target_transform):
            transform = target_transform

    if shape_cast.is_colliding():
        next_step_target = shape_cast.get_collision_point(0)

        if can_step():
            is_moving = true
            step_target = next_step_target
            step_current = target.position
            step_delta = (step_target - step_current).length()

    if is_moving:
        step_current = step_current.move_toward(
                step_target,
                state.step * step_delta
                * travel_speed
                * 2.24
        )

        var progress: float = sin(PI * ((step_delta - (step_target - step_current).length()) / step_delta))

        target.position = step_current + (state.transform.basis.y * progress * leg_lift_height)
        var swing: Vector3 = state.transform.basis.x * progress * leg_swing_offset
        if is_left:
            swing *= -1.0
        target.position += swing

        if step_current.distance_squared_to(step_target) < 1e-4:
            is_moving = false

func setup_shape() -> void:
    shape_rid = PhysicsServer3D.sphere_shape_create()
    PhysicsServer3D.shape_set_data(shape_rid, (shape_cast.shape as SphereShape3D).radius)
    PhysicsServer3D.shape_set_margin(shape_rid, shape_cast.shape.margin)

func can_step() -> bool:
    # Must be not moving
    if is_moving:
        return false

    # Adjacent legs must be not moving
    for leg in get_adjacent():
        if leg.is_moving:
            return false

    return next_step_target.distance_squared_to(target.position) >= step_distance * step_distance

## Returns the legs ahead, behind, and across from this leg.
func get_adjacent() -> Array[CrawlerLeg]:
    var result: Array[CrawlerLeg]
    var max_id: int = body.legs.size()

    # Ahead
    var idx: int = index - 2
    if idx >= 0 and idx < max_id:
        result.append(body.legs[idx])

    # Behind
    idx = index + 2
    if idx >= 0 and idx < max_id:
        result.append(body.legs[idx])

    # Across
    if index % 2 == 0:
        idx = index + 1
    else:
        idx = index - 1

    if idx >= 0 and idx < max_id:
        result.append(body.legs[idx])

    return result
