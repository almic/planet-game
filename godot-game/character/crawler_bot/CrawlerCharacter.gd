@tool
class_name CrawlerCharacter extends CharacterController


@export_range(0.01, 8.0, 0.01, 'or_greater')
var max_speed: float = 3.0

@export var leg_ik: IterateIK3D

var legs: Array[CrawlerLeg]


var target_position: Vector3 = Vector3.INF
var target_direction: Vector3 = Vector3.INF


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

    leg_ik.active = not Engine.is_editor_hint()

func _handle_input() -> void:

    if target_position.is_finite() and (target_position - position).length_squared() > 4.0:
        desired_direction = (target_position - position).normalized()
        desired_speed = max_speed
    elif not desired_direction.is_zero_approx():
        desired_direction = Vector3.ZERO
        desired_speed = 0.0
        target_position = Vector3.INF


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    _update_legs(state)

    if target_direction.is_finite():
        pass

    super._integrate_forces(state)

func _update_legs(state: PhysicsDirectBodyState3D) -> void:

    for leg in legs:
        leg.update(state)


func _calculate_ground_force(state: PhysicsDirectBodyState3D) -> void:

    desired_acceleration = -state.total_gravity

    ground_normal = Vector3.UP
    ground_rel_con_velocity = state.linear_velocity
    ground_velocity = ground_rel_con_velocity.slide(ground_normal)
    ground_friction = Vector3.ZERO

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO

    # TODO: I don't like how this uses desired_acceleration... either make this
    #       write to ground_friction, or make desired_acceleration BETTER (???)
    if has_desired_forward and (not ground_direction.is_zero_approx()):
        # If any legs are not moving and uncomfortable, slow down
        for leg in legs:
            if (not leg.is_moving) and (not leg.is_comfortable):
                var stopping: Vector3 = -ground_direction * deceleration
                var decel_limit: float = ground_velocity.dot(ground_direction) / state.step
                stopping = stopping.limit_length(decel_limit)
                desired_acceleration += stopping
                break

    is_on_floor = true
