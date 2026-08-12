## Helper to estimate point constraint responses between two bodies.
## This is effectively an implementation of Jolt PointConstraintPart.
extends RefCounted


## Constraint position relative to parent center of mass
var parent_rel: Vector3
## Constraint position relative to body center of mass
var body_rel: Vector3

var _r1: Vector3
var _r2: Vector3

var _inv_r1: Basis
var _inv_r2: Basis

var _effective_mass: Basis
var _total_lambda: Vector3


func _init(
    parent_point: Vector3,
    body_point: Vector3
) -> void:
    parent_rel = parent_point
    body_rel = body_point

func apply_velocity_step(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        lambda: Vector3
) -> bool:
    if lambda == Vector3.ZERO:
        return false

    parent.linear_velocity -= parent.inverse_mass * lambda
    parent.angular_velocity -= _inv_r1 * lambda

    body.linear_velocity += body.inverse_mass * lambda
    body.angular_velocity += _inv_r2 * lambda

    return true

func set_total_lambda(total_lambda: Vector3) -> void:
    _total_lambda = total_lambda

func setup(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> void:
    _r1 = parent.transform.basis * parent_rel
    _r2 = body.transform.basis * body_rel

    var summed_inv_mass: float
    var inv_effective_mass: Basis

    var inv_i1: Basis = parent.inverse_inertia_tensor
    summed_inv_mass = parent.inverse_mass

    var r1x: Basis = _cross(_r1)
    _inv_r1 = inv_i1 * r1x
    inv_effective_mass = r1x * inv_i1 * r1x.transposed()

    var inv_i2 = body.inverse_inertia_tensor
    summed_inv_mass += body.inverse_mass

    var r2x: Basis = _cross(_r2)
    _inv_r2 = inv_i2 * r2x
    inv_effective_mass = _add(inv_effective_mass, r2x * inv_i2 * r2x.transposed())

    inv_effective_mass = _add(inv_effective_mass, Basis.from_scale(Vector3.ONE * summed_inv_mass))
    if inv_effective_mass.determinant() == 0.0:
        _effective_mass = Basis.from_scale(Vector3.ZERO)
        _total_lambda = Vector3.ZERO
    else:
        _effective_mass = inv_effective_mass.inverse()

func warm_start(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> void:
    apply_velocity_step(parent, body, _total_lambda)

func solve_velocity(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> bool:
    var lambda: Vector3 = _effective_mass * (
              parent.linear_velocity - _r1.cross(parent.angular_velocity)
            - body.linear_velocity + _r2.cross(body.angular_velocity)
    )

    _total_lambda += lambda
    return apply_velocity_step(parent, body, lambda)

func solve_position(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        baumgarte: float
) -> bool:
    var body_com: Vector3 = body.transform.origin + body.center_of_mass
    var parent_com: Vector3 = parent.transform.origin + parent.center_of_mass
    var separation: Vector3 = body_com - parent_com + _r2 - _r1
    if separation == Vector3.ZERO:
        return false

    var lambda: Vector3 = _effective_mass * -baumgarte * separation

    var xform: Transform3D = parent.transform
    xform.origin -= parent.inverse_mass * lambda
    xform.basis = _sub_rotation(xform.basis, _inv_r1 * lambda)
    parent.transform = xform

    xform = body.transform
    xform.origin += body.inverse_mass * lambda
    xform.basis = _add_rotation(xform.basis, _inv_r2 * lambda)
    body.transform = xform

    return true

func _cross(v: Vector3) -> Basis:
    return Basis(
            Vector3(0, v.z, -v.y),
            Vector3(-v.z, 0, v.x),
            Vector3(v.y, -v.x, 0)
    )

func _add(a: Basis, b: Basis) -> Basis:
    var c: Basis
    c.x = a.x + b.x
    c.y = a.y + b.y
    c.z = a.z + b.z
    return c

func _add_rotation(
        basis: Basis,
        rotation: Vector3
) -> Basis:
    var length: float = rotation.length()
    if length > 1e-6:
        return basis.rotated(rotation / length, length).orthonormalized()
    return basis

func _sub_rotation(
        basis: Basis,
        rotation: Vector3
) -> Basis:
    var length: float = rotation.length()
    if length > 1e-6:
        return basis.rotated(rotation / length, -length).orthonormalized()
    return basis
