## Uses a combination of SixDOFConstraint and DistanceConstraint to allow
## sliding and rotating along a track. The joint X axis is the track, which can
## pivot on the Z axis to allow the bodies some rotational freedom. The two are
## then limited by the DistanceConstraint to stop the fixed points from getting
## too far or too close.
@tool
class_name BeamPivotJoint3D extends Generic6DOFJoint3D


@export var setting: BeamPivotJoint3DSetting:
    set = set_setting

## Additional offset from Body A, applied on top of the setting. Useful to share
## settings but construct joints with unique offsets.
@export var body_A_offset: Vector3

## Helper view to see the initial length of the beam given the current locations
## of the two bodies and their attachment points
@export_custom(PROPERTY_HINT_NONE, '', PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var beam_span: float

## Helper view to see the angle difference between the bodies after the joint
## has initially configured
@export_custom(PROPERTY_HINT_NONE, 'suffix:°', PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var beam_angle: float
var _beam_initial_orientation: Quaternion = Quaternion(0, 0, 0, 0)


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

func _enter_tree() -> void:
    connect_resource()
    set_notify_transform(Engine.is_editor_hint())

func _exit_tree() -> void:
    disconnect_resource()
    set_notify_transform(false)

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSFORM_CHANGED:
        if debug_show_points:
            _queue_update_joint()

func _validate_property(property: Dictionary) -> void:
    # Hide linear and angular limits so we maintain full control
    if property.name.begins_with('angular_') or property.name.begins_with('linear_'):
        property.usage = PROPERTY_USAGE_NONE

# Update joint when nodes change
func _set(property: StringName, value: Variant) -> bool:
    if property == &'node_a' or property == &'node_b':
        _queue_update_joint()
    elif property == &'solver_priority':
        if distance_joint:
            distance_joint.solver_priority = value
    return false

func set_setting(new_setting: BeamPivotJoint3DSetting) -> void:
    disconnect_resource()
    setting = new_setting
    connect_resource()

func connect_resource() -> void:
    if setting and not setting.changed.is_connected(on_setting_changed):
        setting.changed.connect(on_setting_changed)

func disconnect_resource() -> void:
    if setting and setting.changed.is_connected(on_setting_changed):
        setting.changed.disconnect(on_setting_changed)

func on_setting_changed() -> void:
    _queue_update_joint()

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

    exclude_nodes_from_collision = false

    if (not body_a) or (not body_b):
        push_error('Missing a body node, both nodes must be set for BeamJoint3D')
        return

    global_position = body_b.global_transform * setting.body_B_position
    var beam_displacement: Vector3 = (body_a.global_transform * (setting.body_A_position + body_A_offset)) - global_position
    global_basis = _calculate_orientation(beam_displacement)
    if _beam_initial_orientation.w == 0:
        _beam_initial_orientation = global_basis.get_rotation_quaternion()

    # Allow free movement on joint XY plane, distance constraint will
    # handle this limitation
    set_flag_x(FLAG_ENABLE_LINEAR_LIMIT, false)
    set_flag_y(FLAG_ENABLE_LINEAR_LIMIT, false)

    # Restrict joint Z translations if no yaw is enabled
    if setting.yaw_lower > 0.0 or setting.yaw_upper > 0.0:
        set_flag_z(FLAG_ENABLE_LINEAR_LIMIT, false)
    else:
        set_flag_z(FLAG_ENABLE_LINEAR_LIMIT, true)
        set_param_z(PARAM_LINEAR_LOWER_LIMIT, 0.0)
        set_param_z(PARAM_LINEAR_UPPER_LIMIT, 0.0)

    # Restrict all rotations
    # NOTE: I don't understand, but these must be flipped to stay with
    #       the common "positive is counter-clockwise" thing in Godot
    set_flag_x(FLAG_ENABLE_ANGULAR_LIMIT, true)
    set_param_x(PARAM_ANGULAR_LOWER_LIMIT, -setting.pitch_upper)
    set_param_x(PARAM_ANGULAR_UPPER_LIMIT, setting.pitch_lower)

    set_flag_y(FLAG_ENABLE_ANGULAR_LIMIT, true)
    set_param_y(PARAM_ANGULAR_LOWER_LIMIT, -setting.yaw_upper)
    set_param_y(PARAM_ANGULAR_UPPER_LIMIT, setting.yaw_lower)

    set_flag_z(FLAG_ENABLE_ANGULAR_LIMIT, true)
    set_param_z(PARAM_ANGULAR_LOWER_LIMIT, -setting.roll_upper)
    set_param_z(PARAM_ANGULAR_UPPER_LIMIT, setting.roll_lower)

    beam_span = beam_displacement.length()
    beam_angle = rad_to_deg(global_basis.get_rotation_quaternion().angle_to(_beam_initial_orientation))
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
        distance_joint.ready.connect(
            (
                func():
                    distance_joint.node_a = distance_joint.get_path_to(body_a)
                    distance_joint.node_b = distance_joint.get_path_to(body_b)
                    ),
            CONNECT_ONE_SHOT
        )

    if distance_joint.is_inside_tree():
        distance_joint.node_a = distance_joint.get_path_to(body_a)
        distance_joint.node_b = distance_joint.get_path_to(body_b)

    distance_joint.set_param(DistanceJoint3D.PARAM_DISTANCE_MAX, beam_span + setting.expand_limit)
    distance_joint.set_param(DistanceJoint3D.PARAM_DISTANCE_MIN, maxf(beam_span - setting.contract_limit, 0.0))
    distance_joint.set_point_param(DistanceJoint3D.POINT_PARAM_A, setting.body_A_position + body_A_offset)
    distance_joint.set_point_param(DistanceJoint3D.POINT_PARAM_B, setting.body_B_position)
    distance_joint.exclude_nodes_from_collision = false

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

        # When transforming, must call this to make gizmos render correctly
        marker.update_gizmos()

func get_total_applied_force() -> float:
    var force: float = get_applied_force()
    var torque: float = get_applied_torque()

    if distance_joint:
        force += distance_joint.get_applied_force()

    return force + torque
