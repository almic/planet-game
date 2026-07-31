## Helper to estimate angle constraint responses between two bodies.
## This is effectively an implementation of Jolt AngleConstraintPart.
extends RefCounted


var _inv_i1: Vector3
var _inv_i2: Vector3
var _effective_mass: float
var _total_lambda: float


func setup(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        world_axis: Vector3,
) -> void:
    _inv_i1 = parent.inverse_inertia_tensor * world_axis
    _inv_i2 = body.inverse_inertia_tensor * world_axis

    var inv_effective_mass: float = world_axis.dot(_inv_i1 + _inv_i2)
    if inv_effective_mass == 0.0:
        deactivate()
        return

    _effective_mass = 1.0 / inv_effective_mass

func deactivate():
    _effective_mass = 0.0
    _total_lambda = 0.0
