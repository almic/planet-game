class_name BalanceBody2D extends RigidBody2D


var force_points: Array[ForcePoint2D]
var spinning: bool = false


func _ready() -> void:
    force_points.assign(find_children('', 'ForcePoint2D', false))
    #InputManager.pause()
    print(force_points)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    state.linear_velocity += state.total_gravity * state.step
    if not spinning:
        spinning = true
        state.angular_velocity = 0.5

    var count: int = force_points.size()

    var forces: PackedFloat64Array = []
    forces.resize(count)
    forces.fill(1.0 / float(count))

    #forces = [0.295, 0.601, 0.104]
    #forces = [0.43051179, 0.43051179, 0.13897642]

    var total: float
    for iter in range(1):
        var grads: PackedFloat64Array = []
        grads.resize(count)

        for i in range(count):
            var point: Vector2 = force_points[i].global_position - state.transform.origin
            var impulse: Vector2 = -state.total_gravity * forces[i]
            var grad: float = state.inverse_inertia * (point - state.center_of_mass).cross(impulse)

            # equivalent to:
            #     state.apply_impulse(-state.total_gravity * forces[i], point)
            # state.linear_velocity += impulse * state.inverse_mass
            # state.angular_velocity += grad

            grads[i] = grad

        total = 0.0
        for g in grads:
            total += g

        # print(grads)
        # breakpoint

        if is_zero_approx(total):
            break

        var new_forces: PackedFloat64Array = []
        new_forces.resize(count)
        var rescale: float = 0.0
        for i in range(count):
            var new_force: float = grads[i] / forces[i]
            new_force = (new_force - total) / new_force
            #if new_force < 0.0:
                #new_force = -new_force
            new_force = forces[i] + (forces[i] * (new_force - 1.0))

            new_forces[i] = new_force
            rescale += new_force

        for i in range(count):
            forces[i] = new_forces[i] / rescale

    for i in range(count):
        var point: Vector2 = force_points[i].global_position - state.transform.origin
        var impulse: Vector2 = -state.total_gravity * forces[i]

        state.apply_impulse(impulse, point)
        #state.linear_velocity += impulse * state.inverse_mass
        #state.angular_velocity += grad

    print(forces)
    if not is_equal_approx(state.angular_velocity, 0.5):
        breakpoint
    if not state.linear_velocity.is_zero_approx():
        breakpoint
    # breakpoint
