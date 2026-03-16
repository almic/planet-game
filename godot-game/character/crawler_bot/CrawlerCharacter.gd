@tool
class_name CrawlerCharacter extends CharacterController


@export_range(0.01, 8.0, 0.01, 'or_greater')
var max_speed: float = 5.0

@export var leg_ik: IterateIK3D

var legs: Array[CrawlerLeg]


var target_position: Vector3 = Vector3.INF


func _ready() -> void:
    super._ready()

    # Load legs from children
    legs.assign(find_children('', 'CrawlerLeg'))

    var index: int = 0
    for leg in legs:
        leg.body = self
        leg.index = index

        index += 1

        # Copy collision mask to casters
        leg.shape_cast.collision_mask = collision_mask

        # Fix markers in editor
        if Engine.is_editor_hint() and leg.target.top_level:
            leg.target.translate(global_position)
            leg.target.top_level = false

    leg_ik.active = not Engine.is_editor_hint()

func _handle_input() -> void:
    if target_position.is_finite() and (target_position - position).length_squared() > 4.0:
        desired_direction = (target_position - position).normalized()
        desired_speed = 1.0
    elif not desired_direction.is_zero_approx():
        desired_direction = Vector3.ZERO
        desired_speed = 0.0
        target_position = Vector3.INF

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    _update_legs(state)

    super._integrate_forces(state)

func _update_legs(state: PhysicsDirectBodyState3D) -> void:

    for leg in legs:
        leg.update(state)


func _calculate_ground_force(state: PhysicsDirectBodyState3D) -> void:

    desired_acceleration = -state.total_gravity

    ground_normal = Vector3.UP
    ground_rel_con_velocity = state.linear_velocity
    ground_velocity = ground_rel_con_velocity.slide(ground_normal)

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO
