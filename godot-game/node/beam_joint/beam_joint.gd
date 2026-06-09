## Uses a combination of SixDOFConstraint and DistanceConstraint to allow
## sliding and rotating along a track. The joint X axis is the track, which can
## pivot on the Z axis to allow the bodies some rotational freedom. The two are
## then limited by the DistanceConstraint to stop the fixed points from getting
## too far or too close.
@tool
class_name BeamPivotJoint3D extends Generic6DOFJoint3D


## Location of the attachment on Body A
@export
var body_A_position: Vector3 = Vector3.ZERO:
    set(value):
        body_A_position = value
        _queue_update_joint()

## Location of the attachment on Body B
@export
var body_B_position: Vector3 = Vector3.ZERO:
    set(value):
        body_B_position = value
        _queue_update_joint()

## Helper view to see the initial length of the beam given the current locations
## of the two bodies and their attachment points
@export_custom(PROPERTY_HINT_NONE, '', PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var beam_span: float

## Additional expansion allowed between the two attachment points
@export_range(0.0, 1.0, 0.01, 'or_greater')
var expand_limit: float = 0.1:
    set(value):
        expand_limit = value
        _queue_update_joint()

## Additional contraction allowed between the two attachment points, will be
## effectively limited by the initial beam span length
@export_range(0.0, 1.0, 0.01, 'or_greater')
var contract_limit: float = 0.1:
    set(value):
        contract_limit = value
        _queue_update_joint()


@export_group('Pitch', 'pitch')

## Maximum counter-clockwise pitch rotation of the joint on Body B. Should be
## wide enough to allow the bodies to rotate through the beam.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var pitch_upper: float = deg_to_rad(15.0):
    set(value):
        pitch_upper = value
        _queue_update_joint()

## Maximum clockwise pitch rotation of the joint on Body B. Should be wide
## enough to allow the bodies to rotate through the beam.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var pitch_lower: float = deg_to_rad(15.0):
    set(value):
        pitch_lower = value
        _queue_update_joint()


@export_group('Yaw', 'yaw')

## Maximum counter-clockwise yaw rotation of the joint on Body B. You may
## consider opening this if one of the bodies is meant to swing along the other.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var yaw_upper: float = 0.0:
    set(value):
        yaw_upper = value
        _queue_update_joint()

## Maximum clockwise yaw rotation of the joint on Body B.  You may consider
## opening this if one of the bodies is meant to swing along the other.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var yaw_lower: float = 0.0:
    set(value):
        yaw_lower = value
        _queue_update_joint()


@export_group('Roll', 'roll')

## Maximum counter-clockwise roll rotation of the joint on Body B. You probably
## do not want this to be open at all.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var roll_upper: float = 0.0:
    set(value):
        roll_upper = value
        _queue_update_joint()

## Maximum clockwise rotation of the joint on Body B.  You may consider opening
## this if one of the bodies is meant to swing along the other.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var roll_lower: float = 0.0:
    set(value):
        roll_lower = value
        _queue_update_joint()


@export_group('Debug', 'debug')

## Places a Marker3D representing the midpoint of the beam
@export var debug_show_points: bool = false:
    set(value):
        debug_show_points = value
        _debug_draw_points()
var _debug_markers: Array[Marker3D] = [null, null, null]


var distance_joint: DistanceJoint3D

var _update_joint_queued: bool = false


func _ready() -> void:
    _queue_update_joint()

func _validate_property(property: Dictionary) -> void:
    # Hide linear and angular limits so we maintain full control
    if property.name.begins_with('angular_limit_') or property.name.begins_with('linear_limit_'):
        property.usage &= ~PROPERTY_USAGE_EDITOR

# Update joint when nodes change
func _set(property: StringName, value: Variant) -> bool:
    if property == &'node_a' or property == &'node_b':
        _update_joint.call_deferred()
    elif property == &'solver_priority':
        if distance_joint:
            distance_joint.solver_priority = value
    return false

func _queue_update_joint() -> void:
    if _update_joint_queued:
        return
    _update_joint_queued = true
    _update_joint.call_deferred()

func _update_joint() -> void:
    _update_joint_queued = false

    if not is_inside_tree():
        return

    var body_a: PhysicsBody3D = get_node_or_null(node_a)
    var body_b: PhysicsBody3D = get_node_or_null(node_b)

    if (not body_a) or (not body_b):
        push_error('Missing a body node, both nodes must be set for BeamJoint3D')
        return

    global_position = body_b.global_transform * body_B_position
    var beam_displacement: Vector3 = (body_a.global_transform * body_A_position) - global_position
    global_basis = _calculate_orientation(beam_displacement)

    # Allow free movement on joint XY plane, distance constraint will
    # handle this limitation
    set_flag_x(FLAG_ENABLE_LINEAR_LIMIT, false)
    set_flag_y(FLAG_ENABLE_LINEAR_LIMIT, false)

    # Restrict joint Z translations if no yaw is enabled
    if yaw_lower > 0.0 or yaw_upper > 0.0:
        set_flag_z(FLAG_ENABLE_LINEAR_LIMIT, false)
    else:
        set_flag_z(FLAG_ENABLE_LINEAR_LIMIT, true)
        set_param_z(PARAM_LINEAR_LOWER_LIMIT, 0.0)
        set_param_z(PARAM_LINEAR_UPPER_LIMIT, 0.0)

    # Restrict all rotations
    # NOTE: I don't understand, but these must be flipped to stay with
    #       the common "positive is counter-clockwise" thing in Godot
    set_flag_x(FLAG_ENABLE_ANGULAR_LIMIT, true)
    set_param_x(PARAM_ANGULAR_LOWER_LIMIT, -roll_upper)
    set_param_x(PARAM_ANGULAR_UPPER_LIMIT, roll_lower)

    set_flag_y(FLAG_ENABLE_ANGULAR_LIMIT, true)
    set_param_y(PARAM_ANGULAR_LOWER_LIMIT, -yaw_upper)
    set_param_y(PARAM_ANGULAR_UPPER_LIMIT, yaw_lower)

    set_flag_z(FLAG_ENABLE_ANGULAR_LIMIT, true)
    set_param_z(PARAM_ANGULAR_LOWER_LIMIT, -pitch_upper)
    set_param_z(PARAM_ANGULAR_UPPER_LIMIT, pitch_lower)

    beam_span = beam_displacement.length()
    _debug_draw_points()

    # Don't run any of the rest
    if Engine.is_editor_hint():
        return

    # Apply changes
    # Teleport body A into position for accurate rotations
    var original_position: Vector3 = body_a.global_position
    body_a.global_position -= beam_displacement
    force_update_joint()
    body_a.global_position = original_position

    # Set up distance joint
    if not distance_joint:
        distance_joint = DistanceJoint3D.new()
        distance_joint.solver_priority = solver_priority
        add_child.call_deferred(distance_joint)

    distance_joint.node_a = node_a
    distance_joint.node_b = node_b
    distance_joint.set_param(DistanceJoint3D.PARAM_DISTANCE_MAX, beam_span + expand_limit)
    distance_joint.set_param(DistanceJoint3D.PARAM_DISTANCE_MIN, maxf(beam_span - contract_limit, 0.0))
    distance_joint.set_point_param(DistanceJoint3D.POINT_PARAM_A, body_A_position)
    distance_joint.set_point_param(DistanceJoint3D.POINT_PARAM_B, body_B_position)

func _calculate_orientation(axis: Vector3) -> Basis:
    var forward: Vector3 = axis
    if forward.is_zero_approx():
        return global_basis
    forward = forward.normalized()

    var right: Vector3
    if is_equal_approx(absf(forward.dot(Vector3.UP)), 1.0):
        right = global_basis.x
        if is_equal_approx(absf(forward.dot(right)), 1.0):
            right = Vector3.RIGHT
    else:
        right = forward.cross(Vector3.UP).normalized()

    var up: Vector3 = forward.cross(-right).normalized()

    return Basis(forward, up, right)

func _debug_draw_points() -> void:
    if not Engine.is_editor_hint():
        return

    if not debug_show_points:
        for i in range(3):
            if _debug_markers[i]:
                _debug_markers[i].queue_free()
                _debug_markers[i] = null
        # Search for stale markers that saved previously
        for marker in find_children('', 'Marker3D', false, true):
            if marker.get_meta(&'_beam_joint_owned', false):
                marker.queue_free()
        return

    for i in range(3):
        var marker: Marker3D = _debug_markers[i]
        if not marker:
            marker = Marker3D.new()
            # NOTE: apply a meta value to track between save-and-reloads:
            marker.set_meta(&'_beam_joint_owned', true)
            marker.gizmo_extents = 0.2
            add_child.call_deferred(marker, false)
            marker.set_owner.call_deferred(owner)
            _debug_markers[i] = marker

        if i == 0:
            # Leave 0 at joint location
            pass
        elif i == 1:
            # Midpoint
            marker.position.x = 0.5 * beam_span
        else:
            # Body A
            marker.position.x = beam_span

func get_total_applied_force() -> float:
    var force: float = get_applied_force()
    var torque: float = get_applied_torque()

    if distance_joint:
        force += distance_joint.get_applied_force()

    return force + torque
