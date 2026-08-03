## Helper to estimate rotation constraint responses between two bodies.
## This is effectively an implementation of Jolt SwingTwistConstraintPart.
extends RefCounted


const AngleConstraint = preload("uid://c3f0s01o84oa5")

const FLT_MAX: float = 3.4028235e38

enum Flag {
    TwistXLocked = 1 << 0,
    SwingYLocked = 1 << 1,
    SwingZLocked = 1 << 2,

    TwistXFree = 1 << 3,
    SwingYFree = 1 << 4,
    SwingZFree = 1 << 5,
    SwingYZFree = SwingYFree | SwingZFree
}

enum Clamp {
    TwistMin = 1 << 0,
    TwistMax = 1 << 1,
    SwingYMin = 1 << 2,
    SwingYMax = 1 << 3,
    SwingZMin = 1 << 4,
    SwingZMax = 1 << 5,
    SwingYZ = SwingYMin | SwingYMax | SwingZMin | SwingZMax
}

var _flags: int

var _swing_twist: Array[Quaternion]
## sMin, sMax, cMin, cMax
var _twist_sin_cos: Vector4
## Ymin, Ymax, Zmin, Zmax
var _swing_half: Vector4
## Ymin, Ymax, Zmin, Zmax
var _swing_sin: Vector4
## Ymin, Ymax, Zmin, Zmax
var _swing_cos: Vector4

## The world space axes of this constraint
var axis: Basis

var limit_x: AngleConstraint
var limit_y: AngleConstraint
var limit_z: AngleConstraint


func _init() -> void:
    _swing_twist.resize(2)

    axis = Basis.from_scale(Vector3.ZERO)
    limit_x = AngleConstraint.new()
    limit_y = AngleConstraint.new()
    limit_z = AngleConstraint.new()


func set_limits(
        twist_x_min: float, twist_x_max: float,
        swing_y_min: float, swing_y_max: float,
        swing_z_min: float, swing_z_max: float,
) -> void:
    const LOCKED: float = deg_to_rad(0.5)
    const FREE: float = deg_to_rad(179.5)

    _flags = 0
    if twist_x_min > -LOCKED and twist_x_max < LOCKED:
        _flags |= Flag.TwistXLocked
        _twist_sin_cos = Vector4(0.0, 0.0, 1.0, 1.0)
    elif twist_x_min < -FREE and twist_x_max > FREE:
        _flags |= Flag.TwistXFree
        _twist_sin_cos = Vector4(-1.0, 1.0, 0.0, 0.0)
    else:
        _twist_sin_cos = 0.5 * Vector4(twist_x_min, twist_x_max, 0, 0)
        _twist_sin_cos = Vector4(
                sin(_twist_sin_cos.x), sin(_twist_sin_cos.y),
                cos(_twist_sin_cos.x), cos(_twist_sin_cos.y),
        )

    _swing_half = 0.5 * Vector4(swing_y_min, swing_y_max, swing_z_min, swing_z_max)

    if swing_y_min > -LOCKED and swing_y_max < LOCKED:
        _flags |= Flag.SwingYLocked
        _swing_sin.x = 0.0
        _swing_sin.y = 0.0
        _swing_cos.x = 1.0
        _swing_cos.y = 1.0
    elif swing_y_min < -FREE and swing_y_max > FREE:
        _flags |= Flag.SwingYFree
        _swing_sin.x = -1.0
        _swing_sin.y = 1.0
        _swing_cos.x = 0.0
        _swing_cos.y = 0.0
    else:
        _swing_sin.x = sin(_swing_half.x)
        _swing_sin.y = sin(_swing_half.y)
        _swing_cos.x = cos(_swing_half.x)
        _swing_cos.y = cos(_swing_half.y)

    if swing_z_min > -LOCKED and swing_z_max < LOCKED:
        _flags |= Flag.SwingZLocked
        _swing_sin.z = 0.0
        _swing_sin.w = 0.0
        _swing_cos.z = 1.0
        _swing_cos.w = 1.0
    elif swing_z_min < -FREE and swing_z_max > FREE:
        _flags |= Flag.SwingZFree
        _swing_sin.z = -1.0
        _swing_sin.w = 1.0
        _swing_cos.z = 0.0
        _swing_cos.w = 0.0
    else:
        _swing_sin.z = sin(_swing_half.z)
        _swing_sin.w = sin(_swing_half.w)
        _swing_cos.z = cos(_swing_half.z)
        _swing_cos.w = cos(_swing_half.w)

func setup(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        constraint_rotation: Quaternion,
        constraint_world: Quaternion
) -> void:
    _get_swing_twist(constraint_rotation, _swing_twist)
    var swing: Quaternion = _swing_twist[0]

    var clamped_axis: int = _clamp_swing_twist(_swing_twist)
    var clamped_swing: Quaternion = _swing_twist[0]

    if _flags & Flag.SwingYLocked:
        var twist_world: Quaternion = constraint_world * swing
        axis.y = twist_world * Vector3(0, 1, 0)
        axis.z = twist_world * Vector3(0, 0, 1)
        limit_y.setup(parent, body, axis.y)

        if _flags & Flag.SwingZLocked:
            limit_z.setup(parent, body, axis.z)
        elif clamped_axis & (Clamp.SwingZMin | Clamp.SwingZMax) != 0:
            if clamped_axis & Clamp.SwingYMin != 0:
                axis.z = -axis.z
            limit_z.setup(parent, body, axis.z)
        else:
            limit_z.deactivate()
    elif _flags & Flag.SwingZLocked:
        var twist_world: Quaternion = constraint_world * swing
        axis.y = twist_world * Vector3(0, 1, 0)
        axis.z = twist_world * Vector3(0, 0, 1)
        limit_z.setup(parent, body, axis.z)

        if clamped_axis & (Clamp.SwingYMin | Clamp.SwingYMax) != 0:
            if clamped_axis & Clamp.SwingYMin != 0:
                axis.y = -axis.y
            limit_y.setup(parent, body, axis.y)
        else:
            limit_y.deactivate()
    elif _flags & Flag.SwingYZFree != Flag.SwingYZFree:
        limit_z.deactivate()
        if clamped_axis & Clamp.SwingYZ != 0:
            var current: Vector3 = (constraint_world * swing) * Vector3(1, 0, 0)
            var desired: Vector3 = (constraint_world * clamped_swing) * Vector3(1, 0, 0)
            axis.y = desired.cross(current)
            var length: float = axis.y.length()
            if length != 0.0:
                axis.y = axis.y / length
                limit_y.setup(parent, body, axis.y)
            else:
                limit_y.deactivate()
        else:
            limit_y.deactivate()
    else:
        limit_y.deactivate()
        limit_z.deactivate()

    if _flags & Flag.TwistXLocked:
        axis.x = (constraint_world * swing) * Vector3(1, 0, 0)
        limit_x.setup(parent, body, axis.x)
    elif _flags & Flag.TwistXFree == 0:
        if clamped_axis & (Clamp.TwistMin | Clamp.TwistMax) != 0:
            axis.x = (constraint_world * swing) * Vector3(1, 0, 0)
            if clamped_axis & Clamp.TwistMin != 0:
                axis.x = -axis.x
            limit_x.setup(parent, body, axis.x)
        else:
            limit_x.deactivate()
    else:
        limit_x.deactivate()


func _get_swing_twist(rot: Quaternion, swing_twist: Array[Quaternion]) -> void:
    var s: float = sqrt(rot.w * rot.w + rot.x * rot.x)
    if s != 0.0:
        # match order from Jolt
        swing_twist[1] = Quaternion(rot.x / s, 0, 0, rot.w / s)
        swing_twist[0] = Quaternion(
                0,
                (rot.w * rot.y - rot.x * rot.z) / s,
                (rot.w * rot.z + rot.x * rot.y) / s,
                s
        )
    else:
        swing_twist[1] = Quaternion.IDENTITY
        swing_twist[0] = rot

func _dist_to_min_shorter(delta_min: float, delta_max: float) -> bool:
    delta_min = absf(delta_min)
    delta_max = absf(delta_max)
    if delta_min > 1.0:
        delta_min = 2.0 - delta_min
    if delta_max > 1.0:
        delta_max = 2.0 - delta_max
    return delta_min < delta_max

func _clamp_swing_twist(io_swing_twist: Array[Quaternion]) -> int:
    var clamped_axis: int = 0
    var swing: Quaternion = io_swing_twist[0]
    var twist: Quaternion = io_swing_twist[1]

    var negate_swing: bool = swing.w < 0.0
    var negate_twist: bool = twist.w < 0.0
    if negate_swing:
        swing = -swing
    if negate_twist:
        twist = -twist

    if _flags & Flag.TwistXLocked:
        if twist.x != 0.0:
            clamped_axis |= Clamp.TwistMin | Clamp.TwistMax
        twist = Quaternion.IDENTITY
    elif _flags & Flag.TwistXFree == 0:
        var delta_min: float = _twist_sin_cos.x - twist.x
        var delta_max: float = twist.x - _twist_sin_cos.y
        if delta_min > 0.0 or delta_max > 0.0:
            if _dist_to_min_shorter(delta_min, delta_max):
                twist = Quaternion(_twist_sin_cos.x, 0, 0, _twist_sin_cos.z)
                clamped_axis |= Clamp.TwistMin
            else:
                twist = Quaternion(_twist_sin_cos.y, 0, 0, _twist_sin_cos.w)
                clamped_axis |= Clamp.TwistMax

    if _flags & Flag.SwingYLocked:
        if swing.y != 0.0:
            clamped_axis |= Clamp.SwingYMin | Clamp.SwingYMax

        if _flags & Flag.SwingZLocked:
            if swing.z != 0.0:
                clamped_axis |= Clamp.SwingZMin | Clamp.SwingZMax
            swing = Quaternion.IDENTITY
        else:
            var delta_min: float = _swing_sin.z - swing.z
            var delta_max: float = swing.z - _swing_sin.w
            if delta_min > 0.0 or delta_max > 0.0:
                if _dist_to_min_shorter(delta_min, delta_max):
                    swing = Quaternion(0, 0, _swing_sin.z, _swing_cos.z)
                    clamped_axis |= Clamp.SwingZMin
                else:
                    swing = Quaternion(0, 0, _swing_sin.w, _swing_cos.w)
                    clamped_axis |= Clamp.SwingZMax
            elif clamped_axis & Clamp.SwingYMin != 0:
                swing = Quaternion(0, 0, swing.z, sqrt(1.0 - (swing.z * swing.z)))
    elif _flags & Flag.SwingZLocked:
        if swing.z != 0.0:
            clamped_axis |= Clamp.SwingZMin | Clamp.SwingZMax

        var delta_min: float = _swing_sin.x - swing.y
        var delta_max: float = swing.y - _swing_sin.y
        if delta_min > 0.0 or delta_max > 0.0:
            if _dist_to_min_shorter(delta_min, delta_max):
                swing = Quaternion(0, _swing_sin.x, 0, _swing_cos.x)
                clamped_axis |= Clamp.SwingYMin
            else:
                swing = Quaternion(0, _swing_sin.y, 0, _swing_cos.y)
                clamped_axis |= Clamp.SwingYMax
        elif clamped_axis & Clamp.SwingZMin != 0:
            swing = Quaternion(0, swing.y, 0, sqrt(1.0 - (swing.y * swing.y)))
    else:
        # NOTE: Jolt supports cone or pyramid. Godot seems to enforce pyramid...
        var half_angle: Vector2 = Vector2(atan2(swing.y, swing.w), atan2(swing.z, swing.w))
        var clamped_half_angle: Vector2 = (
            half_angle.max(Vector2(_swing_half.x, _swing_half.z)).min(Vector2(_swing_half.y, _swing_half.w))
        )
        if clamped_half_angle != half_angle:
            var sc: Vector4 = Vector4(
                sin(clamped_half_angle.x), cos(clamped_half_angle.x),
                sin(clamped_half_angle.y), cos(clamped_half_angle.y)
            )
            swing = Quaternion(0, sc.x * sc.w, sc.y * sc.z, sc.y * sc.w).normalized()
            clamped_axis |= Clamp.SwingYZ

    if negate_swing:
        swing = -swing
    if negate_twist:
        twist = -twist

    io_swing_twist[0] = swing
    io_swing_twist[1] = twist
    return clamped_axis

func warm_start(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> void:
    # NOTE: This is the order in Jolt; Y, Z, X
    limit_y.warm_start(parent, body)
    limit_z.warm_start(parent, body)

    limit_x.warm_start(parent, body)

func solve_velocity(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
) -> bool:
    var impulse: bool = false
    var solve_impulse: bool

    if limit_y.is_active():
        var max_angle: float = 0.0
        if _swing_sin.x == _swing_sin.y:
            max_angle = FLT_MAX
        solve_impulse = limit_y.solve_velocity(parent, body, axis.y, -FLT_MAX, max_angle)
        impulse = impulse || solve_impulse

    if limit_z.is_active():
        var max_angle: float = 0.0
        if _swing_sin.z == _swing_sin.w:
            max_angle = FLT_MAX
        solve_impulse = limit_z.solve_velocity(parent, body, axis.z, -FLT_MAX, max_angle)
        impulse = impulse || solve_impulse

    if limit_x.is_active():
        var max_angle: float = 0.0
        if _twist_sin_cos.x == _twist_sin_cos.y:
            max_angle = FLT_MAX
        solve_impulse = limit_y.solve_velocity(parent, body, axis.x, -FLT_MAX, max_angle)
        impulse = impulse || solve_impulse

    return impulse

func solve_position(
        parent: PhysicsDirectBodyState3D,
        body: PhysicsDirectBodyState3D,
        constraint_rotation: Quaternion,
        parent_constraint: Quaternion,
        body_constraint: Quaternion,
        baumgarte: float,
) -> bool:
    _get_swing_twist(constraint_rotation, _swing_twist)
    if _clamp_swing_twist(_swing_twist) == 0:
        return false

    var inv_orientation: Quaternion = body_constraint * (parent_constraint * _swing_twist[0] * _swing_twist[1]).inverse()
    # NOTE: At this point, Jolt creates a temporary RotationEulerConstraintPart,
    #       configures it, and calls solve_position on it. This is overkill for
    #       Godot (objects are massive), so I've inlined the code here.
    var inv_effective_mass: Basis = _add(parent.inverse_inertia_tensor, body.inverse_inertia_tensor)
    var effective_mass: Basis
    if inv_effective_mass.determinant() == 0.0:
        if inv_effective_mass.x == Vector3.ZERO:
            inv_effective_mass.x = Vector3(1, 0, 0)
        if inv_effective_mass.y == Vector3.ZERO:
            inv_effective_mass.y = Vector3(0, 1, 0)
        if inv_effective_mass.z == Vector3.ZERO:
            inv_effective_mass.z = Vector3(0, 0, 1)
        if inv_effective_mass.determinant() == 0.0:
            return false

    effective_mass = inv_effective_mass.inverse()

    var diff: Quaternion = (
              body.transform.basis.get_rotation_quaternion()
            * inv_orientation
            * parent.transform.basis.get_rotation_quaternion().inverse()
    )
    if diff.w < 0.0:
        diff = -diff

    var error: Vector3 = 2.0 * diff.get_euler()
    if error == Vector3.ZERO:
        return false

    var lambda: Vector3 = effective_mass * error * -baumgarte
    _sub_rotation(parent, parent.inverse_inertia_tensor * lambda)
    _add_rotation(body, body.inverse_inertia_tensor * lambda)

    return true

func _add(a: Basis, b: Basis) -> Basis:
    for i in range(3):
        a[i] = a[i] + b[i]
    return a

func _add_rotation(
        body: PhysicsDirectBodyState3D,
        rotation: Vector3
) -> void:
    var length: float = rotation.length()
    if length > 1e-6:
        body.transform.basis = body.transform.basis.rotated(rotation / length, length).orthonormalized()

func _sub_rotation(
        body: PhysicsDirectBodyState3D,
        rotation: Vector3
) -> void:
    var length: float = rotation.length()
    if length > 1e-6:
        body.transform.basis = body.transform.basis.rotated(rotation / length, -length).orthonormalized()
