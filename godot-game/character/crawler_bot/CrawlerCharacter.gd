@tool
class_name CrawlerCharacter extends CharacterController

@export var legs: Array[CrawlerLeg]
@export var leg_ik: IterateIK3D


func _ready() -> void:
    super._ready()

    for leg in legs:
        # Copy collision mask to casters
        leg.shape_cast.collision_mask = collision_mask

        # Fix markers in editor
        if Engine.is_editor_hint() and leg.target.top_level:
            leg.target.translate(global_position)
            leg.target.top_level = false

    leg_ik.active = not Engine.is_editor_hint()

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
