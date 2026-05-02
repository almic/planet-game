class_name BalanceBody3D extends RigidBody3D


var force_points: Array[Node3D]
var forces: PackedFloat64Array
var _debug_points: PackedInt64Array
var _debug_angular_accel: int
var count: int
var anti_gravity: Vector3

var last_angular: Vector3 = Vector3.ZERO

func _ready() -> void:
    force_points.assign(find_children('', 'Marker3D', false))
    count = force_points.size()
    forces.resize(count)
    forces.fill(1.0 / float(count))
    _debug_points.resize(count * 2)
    _debug_points.fill(0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    anti_gravity = -state.total_gravity * state.step / state.inverse_mass

    state.angular_velocity -= state.angular_velocity * state.total_angular_damp * state.step
    state.linear_velocity += state.total_gravity * state.step

    _calculate_forces(state)

    var max_force: float = 0.0
    for f in forces:
        if f > max_force:
            max_force = f

    if is_zero_approx(max_force):
        print('Maximum force is zero! Nothing to do!')
        breakpoint

    var debug_vec: Vector3 = (-state.total_gravity).normalized()
    for i in range(count):
        var point: Vector3 = force_points[i].global_position
        var impulse: Vector3 = forces[i] * anti_gravity

        state.apply_impulse(impulse, point - state.transform.origin)

        _debug_points[i * 2] = DebugDraw.sphere(
                point,
                0.05,
                Color.GOLD,
                _debug_points[i * 2],
                0.05
        )

        _debug_points[i * 2 + 1] = DebugDraw.vector(
                point,
                forces[i] * debug_vec / max_force,
                Color.CRIMSON,
                _debug_points[i * 2 + 1],
                0.05
        )

    if not state.linear_velocity.is_zero_approx():
        print('The object moved!')
        breakpoint

    _debug_angular_accel = DebugDraw.text(
        state.transform.origin + Vector3(0.0, 0.5, 1.0),
        str(state.angular_velocity - last_angular),
        Color.GHOST_WHITE,
        32.0,
        _debug_angular_accel,
        0.02
    )

    last_angular = state.angular_velocity

func _calculate_forces(state: PhysicsDirectBodyState3D) -> void:
    ###############
    ###############
    ### WARNING ###
    ###############
    ###############
    ## This may be out-dated, look into CrawlerCharacter for any changes/ improvements.
    ## For the moment, this code will likely not be touched anymore and could have bugs.

    # NOTE: Parameterize the iteration count
    const MAX_ITERATIONS: int = 5
    # NOTE: parameterize the rate of rest (decay???)
    var decay_rate: float = pow(0.5, state.step)

    var rots: PackedVector3Array
    rots.resize(count)
    rots.fill(Vector3.ZERO)
    var rot_normals: PackedVector3Array
    rot_normals.resize(count)
    rot_normals.fill(Vector3.ZERO)

    var markiplier: float = minf(2.0 / float(count), 1.0)
    var power_avg: float = 1.0 / float(count)
    var it_step: float = 1.0 / float(MAX_ITERATIONS)

    for iteration in range(MAX_ITERATIONS):
        var new_forces := PackedFloat64Array(forces)

        var rot_total: Vector3 = Vector3.ZERO
        for i in range(count):
            var point: Vector3 = force_points[i].global_position - state.transform.origin - state.center_of_mass

            rot_normals[i] = state.inverse_inertia * point.cross(anti_gravity)
            rots[i] = rot_normals[i] * new_forces[i]

            rot_total += rots[i]

        # Scale method, each point moves its work to match what is needed, and is always slowly relaxing
        var force_total: float = 0.0
        for i in range(count):
            var work: float = new_forces[i]
            var max_length: float = rot_normals[i].length()

            var new_work: float = work
            # if (leg.disabled):
            #     new_work *= dead_decay_rate
            if not is_zero_approx(max_length):
                var grad: Vector3 = rots[i]
                var new_grad: Vector3 = grad - (rot_total * markiplier)
                var grad_dir: Vector3 = rot_normals[i] / max_length
                var dot_grad: float = new_grad.dot(grad_dir)

                if dot_grad < 0.0:
                    new_grad = Vector3.ZERO
                else:
                    new_grad = grad_dir * dot_grad

                new_work = new_grad.length() / max_length
                new_work *= pow(decay_rate, new_work / power_avg)

            new_forces[i] = maxf(new_work, 0.0)
            force_total += new_forces[i]

        if force_total > 0.0:
            for i in range(count):
                new_forces[i] /= force_total

        force_total = 0.0
        for i in range(count):
            # NOTE: parameterize the rate of change
            forces[i] = move_toward(forces[i], new_forces[i], 8.0 * state.step * it_step)
            force_total += forces[i]

        if force_total > 1.0:
            for i in range(count):
                forces[i] /= force_total
