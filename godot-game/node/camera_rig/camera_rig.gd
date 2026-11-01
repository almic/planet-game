## Camera rig that handles target interpolation, up-axis alignment, rotation
## offsets, and casting
@tool
class_name CameraRig extends Node3D


const Settings = preload("uid://dbe7mfbny5xis")


const META_YAW: StringName = &'_camera_rig_yaw'
const META_PITCH: StringName = &'_camera_rig_pitch'
const META_OFFSET: StringName = &'_camera_rig_offset'
const META_CAST: StringName = &'_camera_rig_cast'
const META_CAMERA: StringName = &'_camera_rig_camera'

## Labels a Marker3D as owned by this CameraRig
const META_DEBUG_MARKER: StringName = &'_camera_rig_debug_marker'


## Angle of the yaw node
@export_range(-180.0, 180.0, 0.1, 'radians_as_degrees')
var yaw_angle: float = 0.0:
    set = set_yaw

## Angle of the pitch node
@export_range(-90.0, 90.0, 0.1, 'radians_as_degrees')
var pitch_angle: float = 0.0:
    set = set_pitch


@export_group('Arm Cast', 'cast')

## When entering/ exiting arm cast, this is the duration of the interpolation
@export_range(0.01, 1.0, 0.01, 'or_greater', 'suffix:s')
var cast_duration: float = 1.0

## Easing curve for arm cast interpolation
@export_exp_easing
var cast_curve: float = -2.0

## Radius of the sphere for the camera arm cast
@export_range(0.01, 1.0, 0.01, 'or_greater', 'suffix:m')
var cast_radius: float = 0.5:
    set = set_cast_radius

## Collision mask for the camera arm cast
@export_flags_3d_physics
var cast_collision_mask: int = 0:
    set = set_cast_mask


@export_group('Offsets')

## Offset of the pitch node relative to the yaw node
@export var pitch_offset: Vector3 = Vector3.ZERO:
    set(value):
        pitch_offset = value
        if pitch_node:
            pitch_node.position = pitch_offset

## Offset of the camera position relative to the pitch node
@export var final_offset: Vector3 = Vector3.ZERO:
    set(value):
        final_offset = value
        if offset_node:
            offset_node.position = final_offset

@export_group('Pitch Limits', 'pitch')

@export_range(0.0, 89.9, 0.1, 'radians_as_degrees')
var pitch_max_up: float = deg_to_rad(88.0):
    set(value):
        pitch_max_up = value
        _apply_pitch_angle()

@export_range(-89.9, 0.0, 0.1, 'radians_as_degrees')
var pitch_max_down: float = deg_to_rad(-88.0):
    set(value):
        pitch_max_down = value
        _apply_pitch_angle()


@export_group('UP Alignment', 'up_axis')

## How quickly to accumulate a target's UP axis orientation, as a percentage per
## second.
@export_range(0.0, 2.0, 0.01, 'or_greater')
var up_axis_feedback: float = 0.4

## How much of the target's UP axis orientation to match, as a fraction
@export_range(0.0, 1.0, 0.01)
var up_axis_ratio: float = 0.3


@export_group('Debug', 'debug')

## Add markers to the scene to visualize the rotation offsets
@export var debug_show_markers: bool = false:
    set = show_markers


var yaw_node: Node3D
var pitch_node: Node3D
var offset_node: Node3D
var arm_cast: ShapeCast3D

var arm_enabled: bool = false:
    set = set_arm_enabled
var arm_cast_progress: float = 1.0
var arm_cast_start: Vector3 = Vector3.ZERO

var camera: Camera3D = null:
    set = set_camera
var _next_cast_position: Vector3 = Vector3.INF
var _last_cast_position: Vector3 = Vector3.INF
var _cast_delta_time: float = 0.0

var _has_initialized: bool = false
var initial_basis: Basis
var up_basis: Basis = Basis.IDENTITY


## The previous target node the rig was attached to, retained only during
## interpolation and while the node is valid
var last_target: Node3D = null

## If the previous target had a rigid body parent, this is that parent, used
## for accurate velocity tracking and better positional interpolation
var last_target_rigid_body: RigidBody3D = null

## The local position of the rig when a new attachment is made
var last_target_local: Vector3 = Vector3.ZERO

## The last known global position of the rig's previous target local offset,
## retained in case the last target node disappears during interpolation
var last_target_global: Vector3 = Vector3.ZERO

## The last known global velocity of the rig's previous target, retained in case
## the last target node disappears during interpolation, ensures the interpolation
## avoids any abrupt speed changes by predicting future global positions
var last_target_global_velocity: Vector3 = Vector3.ZERO

## The active interpolation's progress. Note that this does not account for
## easing curves.
var progress: float = 0.0

## The active interpolation's easing curve, applied onto the interpolation progress
var curve: float = 1.0

## The active interpolation's duration.
var duration: float = 0.0

## The active interpolation's local target at the start of interpolation
var local_start: Vector3 = Vector3.ZERO

## The active interpolation's global rotation at the start of interpolation
var rotation_start: Basis = Basis.IDENTITY


func _ready() -> void:
    yaw_node = _find_or_create(self, &'yaw_node', META_YAW)
    pitch_node = _find_or_create(yaw_node, &'pitch_node', META_PITCH)
    offset_node = _find_or_create(pitch_node, &'offset_node', META_OFFSET)
    arm_cast = _find_or_create(offset_node, &'arm_cast', META_CAST, &'ShapeCast3D')

    # Force values to update
    yaw_angle = yaw_angle
    _apply_pitch_angle()
    pitch_offset = pitch_offset
    final_offset = final_offset
    cast_radius = cast_radius
    cast_collision_mask = cast_collision_mask
    arm_enabled = arm_enabled

    # Apply shape cast settings
    arm_cast.enabled = arm_enabled
    arm_cast.exclude_parent = true
    arm_cast.collide_with_areas = false
    arm_cast.collide_with_bodies = true
    arm_cast.max_results = 0
    arm_cast.margin = 0.0

func attach(new_target: Node3D, settings: Settings = null) -> void:
    if not _has_initialized:
        reparent(new_target, true)
        initial_basis = global_basis
        position = Vector3.ZERO
        _has_initialized = true
        return

    if not settings:
        settings = Settings.new()

    if settings.enable_initial_xform:
        global_transform = settings.initial_global_xform

    progress = 0.0
    curve = settings.curve
    duration = settings.duration
    rotation_start = global_basis

    if settings.track_previous:
        last_target = self.get_parent() as Node3D
        last_target_global = global_position

        last_target_rigid_body = null
        var parent: Node3D = last_target
        var max_search: int = 10
        while max_search > 0 and parent != null:
            max_search -= 1

            if parent is RigidBody3D:
                last_target_rigid_body = parent
                break

            parent = parent.get_parent() as Node3D

        if last_target_rigid_body:
            last_target_global_velocity = last_target_rigid_body.linear_velocity
            last_target_local = last_target_rigid_body.transform.affine_inverse() * global_position
        else:
            last_target_global_velocity = Vector3.ZERO
            last_target_local = position
    else:
        # NOTE: ensure last_target is null in case this method is called more
        # than once between updates
        last_target = null
        last_target_global = global_position
        last_target_global_velocity = Vector3.ZERO

    reparent(new_target, true)
    local_start = position

func update_camera(delta: float) -> void:
    _interpolate_root(delta)
    _interpolate_camera(delta)

func _interpolate_root(delta: float) -> void:
    if progress != 1.0:
        if duration > 0.0:
            progress = clampf(progress + (delta / duration), 0.0, 1.0)
        else:
            progress = 1.0

        if progress == 1.0:
            last_target = null
            position = Vector3.ZERO

    var target_basis: Basis = initial_basis

    if up_axis_ratio > 0.0:
        var delta_rotation: Quaternion
        if up_axis_feedback > 0.0:
            delta_rotation = Quaternion.IDENTITY.slerp(Quaternion(up_basis.y, get_parent_node_3d().global_basis.y), up_axis_feedback)
        else:
            delta_rotation = Quaternion(up_basis.y, Vector3.UP)

        var delta_angle: float = delta_rotation.get_angle()
        if delta_angle != 0.0:
            if absf(delta_angle) < 1.74e-4:
                up_basis = up_basis.rotated(delta_rotation.get_axis().normalized(), delta_angle)
            else:
                up_basis = up_basis.rotated(delta_rotation.get_axis().normalized(), delta_angle * delta)

        var up_rotation: Quaternion = Quaternion(Vector3.UP, up_basis.y)
        var up_angle: float = up_rotation.get_angle()
        if up_angle != 0.0:
            target_basis = initial_basis.rotated(up_rotation.get_axis().normalized(), up_angle)
            target_basis = initial_basis.slerp(target_basis, up_axis_ratio)

    if progress == 1.0:
        global_basis = target_basis
        return

    if (not is_instance_valid(last_target)) or (not last_target.is_inside_tree()):
        last_target = null
        last_target_rigid_body = null

    var blend: float = ease(progress, curve)
    var parent_xform: Transform3D = get_parent_node_3d().global_transform

    var global_to: Vector3 = parent_xform * local_start.lerp(Vector3.ZERO, blend)
    var global_from: Vector3

    if last_target:
        if last_target_rigid_body:
            global_from = last_target_rigid_body.position + last_target_local
            last_target_global_velocity = last_target_rigid_body.linear_velocity
        else:
            global_from = last_target.global_transform * last_target_local
            last_target_global_velocity = (global_from - last_target_global) / delta
        last_target_global = global_from
    else:
        last_target_global += last_target_global_velocity * delta
        global_from = last_target_global

    global_position = global_from.lerp(global_to, blend)
    global_basis = rotation_start.slerp(target_basis, blend)

func _interpolate_camera(delta: float) -> void:
    if arm_cast_progress != 1.0:
        if cast_duration > 0.0:
            arm_cast_progress = clampf(arm_cast_progress + (delta / cast_duration), 0.0, 1.0)
        else:
            arm_cast_progress = 1.0

        if arm_cast_progress == 1.0 and (not arm_enabled):
            camera.position = Vector3.ZERO
            arm_cast.enabled = false
            return

    elif not arm_enabled:
        return

    # Arm cast is enabled, and progress may or may not be 1.0
    var cast_position: Vector3 = arm_cast.target_position * arm_cast.get_closest_collision_safe_fraction()
    if cast_position != _next_cast_position:
        _last_cast_position = _next_cast_position
        if _last_cast_position == Vector3.INF:
            _last_cast_position = cast_position
        _next_cast_position = cast_position
        _cast_delta_time = 0.0
    _cast_delta_time += delta

    if not camera:
        return

    if not arm_enabled:
        camera.position = arm_cast_start.lerp(Vector3.ZERO, ease(arm_cast_progress, cast_curve))
        return

    var physics_frame_time: float = 1.0 / Engine.physics_ticks_per_second
    if _cast_delta_time >= physics_frame_time:
        cast_position = _next_cast_position
    else:
        cast_position = _last_cast_position.lerp(_next_cast_position, _cast_delta_time / physics_frame_time)

    # Keep camera within cast bounds
    camera.position = _clamp_to_capsule(
            camera.position,
            Vector3.ZERO,
            cast_position,
            maxf(0.0, cast_radius - 0.02)
    )

    if arm_cast_progress < 1.0:
        camera.position = arm_cast_start.lerp(cast_position, ease(arm_cast_progress, cast_curve))
    else:
        var camera_delta: float = (cast_position - camera.position).length()
        if camera_delta < 0.001:
            camera.position = cast_position
        else:
            camera.position = camera.position.lerp(cast_position, minf(1.0, 20.0 * delta))

## Helper to clamp a position in local space to a capsule
func _clamp_to_capsule(
        point: Vector3,
        capsule_a: Vector3,
        capsule_b: Vector3,
        radius: float
) -> Vector3:
    var point_in_capsule: Vector3 = Geometry3D.get_closest_point_to_segment(point, capsule_a, capsule_b)
    var cast_delta: Vector3 = point - point_in_capsule
    if cast_delta.length_squared() > (radius * radius):
        return point_in_capsule + cast_delta.limit_length(radius)
    return point

func set_camera(to: Camera3D) -> void:
    if not is_node_ready():
        push_error('CameraRig: Not allowed to set camera node before rig is ready!')
        return

    camera = to
    camera.reparent(offset_node, false)
    camera.transform = Transform3D.IDENTITY

func set_cast(yaw: float, pitch: float, distance: float) -> void:
    var cast_target: Vector3 = Vector3(0.0, 0.0, distance)
    cast_target = cast_target.rotated(Vector3.UP, yaw)
    cast_target = cast_target.rotated(Vector3.LEFT.rotated(Vector3.UP, yaw), pitch)
    arm_cast.target_position = cast_target

func set_cast_radius(radius: float) -> void:
    cast_radius = radius
    if not arm_cast:
        return

    var shape: SphereShape3D = arm_cast.shape as SphereShape3D
    if not shape:
        shape = SphereShape3D.new()
        arm_cast.shape = shape

    shape.radius = cast_radius

func set_cast_mask(mask: int) -> void:
    cast_collision_mask = mask
    if arm_cast:
        arm_cast.collision_mask = cast_collision_mask

func set_arm_enabled(enabled: bool) -> void:
    arm_enabled = enabled
    if not arm_cast:
        return

    if not camera:
        arm_cast_progress = 1.0
        arm_cast.enabled = arm_enabled
        return

    # Interpolation requires the cast to be active, even though it could be
    # disabled immediately
    arm_cast.enabled = true
    arm_cast_progress = 0.0
    arm_cast_start = camera.position

func set_yaw(angle: float) -> void:
    yaw_angle = angle
    if yaw_node:
        yaw_node.rotation.y = yaw_angle

func set_pitch(angle: float) -> void:
    pitch_angle = angle
    _apply_pitch_angle()

func _apply_pitch_angle() -> void:
    if pitch_node:
        pitch_node.rotation.x = clampf(pitch_angle, pitch_max_down, pitch_max_up)

func show_markers(value: bool = true) -> void:
    debug_show_markers = value
    for node in [yaw_node, pitch_node, offset_node]:
        if not node:
            continue
        if debug_show_markers:
            _add_marker(node)
        else:
            _remove_marker(node)

func _find_or_create(node: Node, node_name: StringName, meta: StringName, default: StringName = &'Node3D') -> Node:
    if not node:
        push_error('CameraRig: Cannot locate/ create node on a null parent!')
        return null

    var found: Node3D = null
    for child in node.get_children():
        if child.has_meta(meta):
            found = child
            break

    if not found:
        found = ClassDB.instantiate(default)
        found.set_meta(meta, true)
        found.name = node_name
        node.add_child(found, true)

    found.owner = node.owner

    return found

func _find_markers(node: Node3D) -> Array[Marker3D]:
    var markers: Array[Marker3D]
    if not node:
        return markers

    for child in node.get_children(true):
        var marker: Marker3D = child as Marker3D
        if marker and marker.has_meta(META_DEBUG_MARKER):
            markers.append(marker)

    return markers

func _add_marker(node: Node3D) -> void:
    if _find_markers(node).size() > 0:
        return

    var marker: Marker3D = Marker3D.new()
    marker.set_meta(META_DEBUG_MARKER, true)
    node.add_child(marker, false, Node.INTERNAL_MODE_FRONT)

func _remove_marker(node: Node3D) -> void:
    var markers: Array[Marker3D] = _find_markers(node)
    for marker in markers:
        marker.queue_free()
