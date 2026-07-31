## Helper to estimate rotation constraint responses between two bodies.
## This is effectively an implementation of Jolt SwingTwistConstraintPart.
extends RefCounted


const AngleConstraint = preload("uid://c3f0s01o84oa5")


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
var _twist_sin_cos: Vector4
var _swing_half: Vector4
var _swing_sin: Vector4
var _swing_cos: Vector4

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

func _clamp_swing_twist(io_swing_twist: Array[Quaternion]) -> int:
    return 0
