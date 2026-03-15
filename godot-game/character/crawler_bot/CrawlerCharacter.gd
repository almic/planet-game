@tool
class_name CrawlerCharacter extends CharacterController

@export var legs: Array[CrawlerLeg]



func _ready() -> void:

    for leg in legs:
        # Copy collision mask to casters
        leg.shape_cast.collision_mask = collision_mask


func _handle_input() -> void:
    desired_direction = Vector3.BACK
    desired_speed = 1.0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    _update_legs(state)

    super._integrate_forces(state)

func _update_legs(state: PhysicsDirectBodyState3D) -> void:
    for leg in legs:
        leg.update()


func _calculate_ground_force(state: PhysicsDirectBodyState3D) -> void:

    desired_acceleration = -state.total_gravity
