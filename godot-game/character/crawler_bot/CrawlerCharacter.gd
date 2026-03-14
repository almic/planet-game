@tool
class_name CrawlerCharacter extends CharacterController

@export var leg_pairs: Array[CrawlerLegPair]



func _ready() -> void:

    for pair in leg_pairs:
        # Ensure targets are top-level
        pair.target_left.top_level = true
        pair.target_right.top_level = true

        # Copy collision mask to casters
        pair.cast_left.collision_mask = collision_mask
        pair.cast_right.collision_mask = collision_mask

func _handle_input() -> void:
    desired_direction = Vector3.BACK
    desired_speed = 1.0

func _calculate_ground_force(state: PhysicsDirectBodyState3D) -> void:

    for pair in leg_pairs:
        # Move targets to collision point
        if pair.cast_left.is_colliding():
            pair.target_left.transform.origin = pair.cast_left.get_collision_point(0)
        if pair.cast_right.is_colliding():
            pair.target_right.transform.origin = pair.cast_right.get_collision_point(0)

    spring_force = -state.total_gravity * mass
