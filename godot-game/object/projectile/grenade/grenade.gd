extends RigidBody3D

var timer: float = 20.0

func _physics_process(delta: float) -> void:
    timer -= delta
    if timer <= 0.0:
        queue_free()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    if state.get_contact_count() < 1:
        return

    var other: RigidBody3D = state.get_contact_collider_object(0) as RigidBody3D
    if not other:
        return

    set_process_mode.call_deferred(Node.PROCESS_MODE_DISABLED)
    queue_free()

    if other.has_method(&'damage'):
        other.damage(self, 1.0, state.get_contact_collider_position(0))
