class_name ProjectileBody extends RigidBody3D

var timer: float = 20.0
var spawning_body: RID:
    set(value):
        var rid := get_rid()
        if spawning_body:
            PhysicsServer3D.body_remove_collision_exception(rid, spawning_body)
        if value:
            PhysicsServer3D.body_add_collision_exception(rid, value)
        spawning_body = value

func _physics_process(delta: float) -> void:
    timer -= delta
    if timer <= 0.0:
        queue_free()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    if spawning_body:
        var rid := get_rid()
        var space := state.get_space_state()
        var query := PhysicsShapeQueryParameters3D.new()
        query.exclude = [rid]
        query.collision_mask = PhysicsServer3D.body_get_collision_mask(spawning_body)

        var intersects_spawner: bool = false

        var shape_count: int = PhysicsServer3D.body_get_shape_count(rid)
        for shape_idx in range(shape_count):
            var shape_rid: RID = PhysicsServer3D.body_get_shape(rid, shape_idx)
            var shape_xform: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, shape_idx)

            # NOTE: Scale by 10% to avoid random collisions with the spawner
            #       that destroy it on the next frame anyway
            shape_xform = shape_xform.scaled(Vector3.ONE * 1.1)

            query.shape_rid = shape_rid
            query.transform = state.transform * shape_xform

            var intersections: Array[Dictionary] = space.intersect_shape(query, 8)
            for hit in intersections:
                if hit.rid == spawning_body:
                    intersects_spawner = true
                    break

            if intersects_spawner:
                break

        if not intersects_spawner:
            PhysicsServer3D.body_remove_collision_exception(rid, spawning_body)
            spawning_body = RID()

    if state.get_contact_count() < 1:
        return

    var other: RigidBody3D = state.get_contact_collider_object(0) as RigidBody3D
    if not other:
        return

    set_process_mode.call_deferred(Node.PROCESS_MODE_DISABLED)
    queue_free()

    if other.has_method(&'damage'):
        other.damage(self, 1.0, state.get_contact_collider_position(0))
