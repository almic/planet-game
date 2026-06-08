class_name BeamPivotJoint3DSetting extends Resource

## Location of the attachment on Body A
@export
var body_A_position: Vector3 = Vector3.ZERO:
    set(value):
        body_A_position = value
        emit_changed()

## Location of the attachment on Body B
@export
var body_B_position: Vector3 = Vector3.ZERO:
    set(value):
        body_B_position = value
        emit_changed()

## Helper view to see the initial length of the beam given the current locations
## of the two bodies and their attachment points
@export_custom(PROPERTY_HINT_NONE, '', PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var beam_span: float

## Additional expansion allowed between the two attachment points
@export_range(0.0, 1.0, 0.01, 'or_greater')
var expand_limit: float = 0.1:
    set(value):
        expand_limit = value
        emit_changed()

## Additional contraction allowed between the two attachment points, will be
## effectively limited by the initial beam span length
@export_range(0.0, 1.0, 0.01, 'or_greater')
var contract_limit: float = 0.1:
    set(value):
        contract_limit = value
        emit_changed()


@export_group('Pitch', 'pitch')

## Maximum counter-clockwise pitch rotation of the joint on Body B. Should be
## wide enough to allow the bodies to rotate through the beam.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var pitch_upper: float = deg_to_rad(15.0):
    set(value):
        pitch_upper = value
        emit_changed()

## Maximum clockwise pitch rotation of the joint on Body B. Should be wide
## enough to allow the bodies to rotate through the beam.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var pitch_lower: float = deg_to_rad(15.0):
    set(value):
        pitch_lower = value
        emit_changed()


@export_group('Yaw', 'yaw')

## Maximum counter-clockwise yaw rotation of the joint on Body B. You may
## consider opening this if one of the bodies is meant to swing along the other.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var yaw_upper: float = 0.0:
    set(value):
        yaw_upper = value
        emit_changed()

## Maximum clockwise yaw rotation of the joint on Body B.  You may consider
## opening this if one of the bodies is meant to swing along the other.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var yaw_lower: float = 0.0:
    set(value):
        yaw_lower = value
        emit_changed()


@export_group('Roll', 'roll')

## Maximum counter-clockwise roll rotation of the joint on Body B. You probably
## do not want this to be open at all.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var roll_upper: float = 0.0:
    set(value):
        roll_upper = value
        emit_changed()

## Maximum clockwise rotation of the joint on Body B.  You may consider opening
## this if one of the bodies is meant to swing along the other.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var roll_lower: float = 0.0:
    set(value):
        roll_lower = value
        emit_changed()
