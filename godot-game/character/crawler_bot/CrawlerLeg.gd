@tool
class_name CrawlerLeg extends Node3D

## The floor step target raycast
@export var shape_cast: ShapeCast3D

## The node that IK uses for this leg
@export var target: Marker3D


@export_group('Ground Detection', 'ground')

@export_custom(PROPERTY_HINT_ENUM, '')
var ground_bone: StringName

## How far back from the ground bone to raycast
@export_range(0.05, 0.2, 0.01, 'or_greater')
var ground_hit_start: float = 0.1

## How far beyond the ground bone to raycast
@export_range(0.05, 0.2, 0.01, 'or_greater')
var ground_hit_extra: float = 0.05


@export_group('Stepping')

## How far between current and rest position to start moving the leg torwards the move target.
## Actual steps will be a little higher than double this value while in motion.
@export_range(0.01, 1.0, 0.01, 'or_greater')
var step_distance: float = 0.5

## If all paired legs are able to step, use this distance as a minimum for early steps.
@export_range(0.0, 0.5, 0.01, 'or_greater')
var early_step_distance: float = 0.15

## When in motion, the angle for the step shape cast, in the direction of motion.
## This pivots about the rest position of the leg.
@export_range(0.0, 45.0, 0.1, 'radians_as_degrees')
var step_cast_angle: float = deg_to_rad(20.0)

## How far between current and rest position the leg should be when at rest.
## This should be very small so the legs return to a comfortable position.
@export_range(0.01, 0.5, 0.01, 'or_greater')
var rest_distance: float = 0.05

## How long this leg must wait before it can step again
@export_range(0.01, 0.5, 0.01, 'or_greater')
var step_delay: float = 0.15

## If a paired leg has started moving in this time frame, allow this leg to
## move early to stay synchronized.
@export_range(0.0, 0.5, 0.01, 'or_greater')
var step_pair_window: float = 0.05

## How long a legs cross-pair (the set of legs that move exclusive to this leg)
## must be grounded before this leg can move.
@export_range(0.0, 0.5, 0.01, 'or_greater')
var step_crosspair_wait: float = 0.05

## How much to lift the leg while taking a step, applies on the body's up axis
@export_range(0.0, 1.0, 0.01, 'or_greater')
var leg_lift_height: float = 0.3

## How much to swing the leg out while taking a step, applies on the body's right axis
@export_range(0.0, 1.0, 0.01, 'or_greater')
var leg_swing_offset: float = 0.2

## When in motion, how far in the direction of travel to shift the leg move target
@export_range(0.0, 1.0, 0.01, 'or_greater')
var move_offset: float = 0.6

## When in motion, how far in the direction of travel to rotate the leg move target.
## For front and back legs, the leg only rotates forward or backward, respectively.
@export_range(0.0, 45.0, 0.1, 'radians_as_degrees')
var move_spin: float = deg_to_rad(15.0)

## How quickly to interpolate in/out of leg move offsets.
@export_range(1.0, 10.0, 0.01, 'or_greater')
var move_interp_rate: float = 10.0


@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false

## The comfort region for leg
@export var debug_rest_area: bool = false
var _debug_rest_circle: int = 0

## The step shape cast
@export var debug_step_cast: bool = false
var _debug_step_cast_shape: int = 0
var _debug_step_cast_vector: int = 0

## The target position for the current step
@export var debug_step_target: bool = false
var _debug_target_sphere: int = 0

## The target IK position for the leg
@export var debug_ik_target: bool = false
var _debug_ik_sphere: int = 0

## The ground contact normal of the leg
@export var debug_ground_normal: bool = false
var _debug_ground_normal_vector: int = 0

## The cast used for ground detection
@export var debug_ground_cast: bool = false
var _debug_ground_cast_vector: int = 0
var _debug_ground_cast_shape: int = 0

## Render text at the leg giving the reason it takes a step
@export var debug_step_reason: bool = false
var _debug_step_reason_text: int = 0


var body: CrawlerCharacter = null:
    set(value):
        body = value
        notify_property_list_changed()
var index: int = -1
var is_left: bool:
    get():
        return index % 2 == 0
var has_initialized: bool = false

## Initial location of the leg position relative to the body
var attachment_point: Vector3 = Vector3.ZERO

## Transform of the leg root when at rest, set when the body enters the scene
var rest_transform: Transform3D

## Position of the leg at rest, set as the target position on the first update
var target_rest_position: Vector3 = Vector3.INF
var target_global_rest: Vector3 = Vector3.INF
var cast_direction: Vector3 = Vector3.INF
var global_cast_direction: Vector3 = Vector3.INF

## The leg is currently touching ground
var is_grounded: bool = false
## How long it has been since the leg collided with ground
var time_since_grounded: float = 0.0

## The leg is currently in motion
var is_moving: bool = false
## How long it has been since the last movement began
var time_since_moved: float = 0.0

## The leg is currently taking a step
var is_stepping: bool = false
## How long it has been since the last step began
var time_since_stepped: float = 0.0

## The leg is in a comfortable position. This is used to signal that the leg
## wants to move to a better position.
var is_comfortable: bool = false

var step_target: Vector3 = Vector3.INF

var step_current: Vector3 = Vector3.INF
var step_delta: float

var comfort_distance: float

var ground_bone_idx: int = -1
var ground_cast: ShapeCast3D
var ground_body: RID
var ground_leg_transform: Transform3D
var ground_normal: Vector3 = Vector3.INF
var ground_point: Vector3 = Vector3.INF
var ground_velocity: Vector3 = Vector3.ZERO
var ground_offset: float = INF

var target_bone_idx: int = -1
var target_bone_position: Vector3

var cached_adjacent: Array[CrawlerLeg]
var cached_diagonal: Array[CrawlerLeg]


func _ready() -> void:
    if not shape_cast:
        for child in find_children('', 'ShapeCast3D', false):
            shape_cast = child as ShapeCast3D
            if shape_cast:
                break
    if not target:
        for child in find_children('', 'Marker3D', false):
            target = child as Marker3D
            if target:
                break

    shape_cast.enabled = false
    rest_transform = transform
    comfort_distance = rest_distance

    # Ensure target is top-level in-game
    target.top_level = not Engine.is_editor_hint()

func _validate_property(property: Dictionary) -> void:
    if property.name == &'ground_bone':
        property.hint = PROPERTY_HINT_ENUM
        if body.skeleton:
            property.hint_string = body.skeleton.get_concatenated_bone_names()

func setup() -> void:
    if not has_initialized:
        has_initialized = true
        target_rest_position = global_transform.inverse() * target.global_position
        cast_direction = shape_cast.target_position.normalized()
        attachment_point = (body.global_transform.inverse() * global_transform).origin

        # Get the chain end bone
        var target_path: NodePath = body.leg_ik.get_path_to(target)
        for setting in range(body.leg_ik.setting_count):
            if body.leg_ik.get_target_node(setting) == target_path:
                target_bone_idx = body.leg_ik.get_end_bone(setting)
                break

        if target_bone_idx == -1:
            push_error(
                'Unable to find end bone targetting node "%s"!' % target.name
            )

        ground_bone_idx = body.skeleton.find_bone(ground_bone)
        # Find a bone attachment with the same bone
        var parent_bone: int = body.skeleton.get_bone_parent(ground_bone_idx)
        var attachments: Array[ModifierBoneTarget3D]
        attachments.assign(body.skeleton.find_children('', 'ModifierBoneTarget3D'))
        for bone_target in attachments:
            if bone_target.bone != parent_bone:
                continue
            ground_cast = ShapeCast3D.new()
            ground_cast.enabled = false
            ground_cast.collision_mask = shape_cast.collision_mask
            # NOTE: Ground cast should share the step cast shape resource (NOT a copy!) so they remain synchronized
            ground_cast.shape = shape_cast.shape
            bone_target.add_child(ground_cast, false, Node.INTERNAL_MODE_FRONT)

            var target_position: Vector3 = body.skeleton.get_bone_pose_position(ground_bone_idx)
            var bone_direction: Vector3 = target_position.normalized()
            var shape_size: float = (ground_cast.shape as SphereShape3D).radius
            var start_position: Vector3 = (bone_direction * (ground_hit_start + shape_size))
            ground_cast.position = target_position - start_position
            ground_cast.target_position = start_position + (bone_direction * (ground_hit_extra - shape_size))

            break

        if not ground_cast:
            push_error(
                    'Leg %s could not find an existing BoneAttachment3D for the bone "%s"! Please create one.' % [
                        name, body.skeleton.get_bone_name(parent_bone)
                    ]
            )

        # Add all children as exclusion for shape cast
        for child_body in body.find_children('', 'CollisionObject3D'):
            if child_body is CollisionObject3D:
                if shape_cast:
                    shape_cast.add_exception_rid(child_body.get_rid())
                if ground_cast:
                    ground_cast.add_exception_rid(child_body.get_rid())

    cached_adjacent = get_adjacent()
    cached_diagonal = get_diagonal()

func update_ground_leg_transform() -> void:
    ground_leg_transform = (
              body.skeleton.global_transform
            * body.skeleton.get_bone_global_pose(body.skeleton.get_bone_parent(ground_bone_idx))
    )
    ground_cast.force_update_transform()
    ground_cast.force_shapecast_update()

    target_bone_position = (
              body.skeleton.global_transform
            * body.skeleton.get_bone_global_pose(target_bone_idx).origin
    )

    if debug_enable and debug_ground_cast:
        var shape_origin: Vector3 = ground_cast.target_position
        var shape_color: Color
        if ground_cast.is_colliding():
            shape_origin *= ground_cast.get_closest_collision_unsafe_fraction()
            shape_color = Color.DARK_SLATE_BLUE
        else:
            shape_color = Color.DARK_SLATE_GRAY

        _debug_ground_cast_vector = DebugDraw.vector(
                ground_cast.global_position,
                ground_cast.global_basis * shape_origin,
                shape_color,
                _debug_ground_cast_vector
        )
        _debug_ground_cast_shape = DebugDraw.sphere(
                ground_cast.global_transform * shape_origin,
                (ground_cast.shape as SphereShape3D).radius,
                shape_color,
                _debug_ground_cast_shape
        )

func update(state: PhysicsDirectBodyState3D) -> void:
    global_cast_direction = state.transform.basis * cast_direction

    var target_transform: Transform3D = rest_transform
    var leg_speed: float

    if body.has_desired_forward:
        leg_speed = body.desired_speed
        target_transform.origin += state.transform.basis.inverse() * body.desired_direction * move_offset

        var is_front: bool = index < 2
        var is_back: bool = index + 2 >= body.legs.size()

        var cos_theta: float = body.desired_direction.dot(-state.transform.basis.z)

        if is_front or is_back:
            cos_theta = absf(cos_theta) * 2.0 - 1.0
            if is_front:
                if is_left:
                    cos_theta *= -1.0
            elif not is_left:
                cos_theta *= -1.0
        elif is_left:
            cos_theta *= -1.0

        target_transform = target_transform.rotated_local(transform.basis.y, move_spin * cos_theta)
    elif transform == target_transform:
        leg_speed = (
                maxf(
                    minf(
                        body.ground_direction.dot(body.ground_velocity),
                        body.max_speed
                    ),
                    body.max_speed / 3.0
                )
        )
    elif is_stepping:
        # Use very small leg speed while interpolating to rest
        leg_speed = maxf(body.max_speed / 20.0, 0.05)
    # TODO: is_moving uses a faster speed (like recovery actions)

    if transform != target_transform:
        # Force at least 0.5cm of travel each interpolation
        # TODO: min travel should be delta'd, needs a multiply by state.step!!
        var min_weight: float = minf(2.5e-5 / transform.origin.distance_squared_to(target_transform.origin), 1.0)
        transform = transform.interpolate_with(target_transform, maxf(state.step * move_interp_rate, min_weight))

        if transform.is_equal_approx(target_transform):
            transform = target_transform

    target_global_rest = global_transform * target_rest_position

    if debug_enable and debug_rest_area:
        _debug_rest_circle = DebugDraw.circle(
                target_global_rest,
                comfort_distance,
                state.transform.basis.y,
                16,
                Color.GREEN,
                _debug_rest_circle,
                1.0
        )

    var has_ground: bool = false
    if ground_cast.is_colliding():
        ground_point = ground_cast.get_collision_point(0)
        ground_normal = ground_cast.get_collision_normal(0)
        var leg_normal: Vector3 = -ground_leg_transform.basis.y

        var ground_cos_theta: float = ground_normal.dot(leg_normal)
        if ground_cos_theta >= 0.0:
            has_ground = true

    if has_ground:
        if not is_grounded:
            is_grounded = true

        ground_body = ground_cast.get_collider_rid(0)
        var ground_state := PhysicsServer3D.body_get_direct_state(ground_body)
        ground_velocity = ground_state.get_velocity_at_local_position(
                    ground_point - ground_state.transform.origin
                )

        if debug_enable and debug_ground_normal:
            _debug_ground_normal_vector = DebugDraw.vector(
                    ground_point,
                    ground_normal * 0.5,
                    Color.CORNFLOWER_BLUE,
                    _debug_ground_normal_vector
            )
    elif is_grounded:
        is_grounded = false
        ground_normal = Vector3.INF
        ground_velocity = Vector3.ZERO
        time_since_grounded = 0.0
        if debug_enable and debug_ground_normal:
            _debug_ground_normal_vector = DebugDraw.vector(
                    Vector3.ZERO,
                    Vector3.ZERO,
                    Color.CORNFLOWER_BLUE,
                    _debug_ground_normal_vector,
                    0.001
            )

    if body.is_stepping:
        comfort_distance = move_toward(comfort_distance, step_distance, state.step * 2.0)
    elif transform.is_equal_approx(rest_transform):
        # TODO: maybe always move comfort distance? Legs should handle moving targets now.
        comfort_distance = move_toward(comfort_distance, rest_distance, state.step * 2.0)

    # Rotate in direction of motion
    var old_shape_cast_xform: Transform3D = shape_cast.transform
    if body.has_desired_forward and not is_zero_approx(step_cast_angle):
        var rot_axis: Vector3 = body.global_basis.inverse() * body.desired_direction.cross(body.global_basis.y)
        rot_axis = rot_axis.normalized()
        var angle: float = step_cast_angle# * (1.0 - absf(body.global_basis.tdoty(body.desired_direction)))
        var point: Vector3 = target_rest_position - shape_cast.position

        # NOTE: Think of making a "transform sandwich", order the lines as if you are looking at
        #       the side profile of a "transform sandwich".
        var xform: Transform3D = Transform3D.IDENTITY
        xform = xform.translated(-point)
        xform = xform.rotated(rot_axis, angle)
        xform = xform.translated(target_rest_position)

        shape_cast.transform = xform

    shape_cast.force_shapecast_update()

    if shape_cast.is_colliding():
        var next_step_target: Vector3 = shape_cast.get_collision_point(0)

        if is_stepping:
            var step_change: float = (next_step_target - step_target).length()
            step_delta = minf(step_delta + step_change, step_distance * 2.0)
            step_target = next_step_target
        elif can_step():
            is_stepping = true
            time_since_stepped = 0.0
            step_target = next_step_target
            step_current = target.position
            step_delta = (step_target - step_current).length()

    if debug_enable:
        if debug_step_cast:
            var shape_origin: Vector3 = shape_cast.target_position
            var shape_color: Color
            if shape_cast.is_colliding():
                shape_origin *= shape_cast.get_closest_collision_unsafe_fraction()
                shape_color = Color.OLIVE_DRAB
            else:
                shape_color = Color.DARK_SLATE_GRAY

            _debug_step_cast_vector = DebugDraw.vector(
                    shape_cast.global_position,
                    shape_cast.global_basis * shape_origin,
                    shape_color,
                    _debug_step_cast_vector
            )
            _debug_step_cast_shape = DebugDraw.sphere(
                    shape_cast.global_transform * shape_origin,
                    (shape_cast.shape as SphereShape3D).radius,
                    shape_color,
                    _debug_step_cast_shape
            )
        if debug_step_target:
            _debug_target_sphere = DebugDraw.sphere(
                    step_target,
                    (shape_cast.shape as SphereShape3D).radius,
                    Color.FIREBRICK * Color(1.0, 1.0, 1.0, 0.3),
                    _debug_target_sphere,
                    1.0
            )

    shape_cast.transform = old_shape_cast_xform

    if is_stepping:
        step_current = step_current.move_toward(
                step_target,
                state.step * step_delta
                * leg_speed
                * 2.24
        )

        var progress: float = sin(PI * ((step_delta - (step_target - step_current).length()) / step_delta))

        target.position = step_current + (state.transform.basis.y * progress * leg_lift_height)
        var swing: Vector3 = state.transform.basis.x * progress * leg_swing_offset * minf(step_delta / step_distance, 1.0)
        if is_left:
            swing *= -1.0
        target.position += swing

        if step_current.distance_squared_to(step_target) < 1e-4:
            is_stepping = false
            target.position = step_target

    if debug_enable and debug_ik_target:
        _debug_ik_sphere = DebugDraw.sphere(
                target.position,
                0.02,
                Color.AQUA,
                _debug_ik_sphere
        )

    # time_since_moved += state.step
    time_since_stepped += state.step

    if is_grounded:
        time_since_grounded += state.step

func can_step() -> bool:
    # Must be not moving
    if is_moving:
        return false

    var dist_sqr: float = distance_squared_to_rest(target.position)
    is_comfortable = dist_sqr <= comfort_distance * comfort_distance

    # When grounded, try yielding to other legs
    if is_grounded:
        # Wait for this leg to remain in place before stepping again
        if time_since_grounded < step_delay or time_since_stepped < step_delay:
            return false

        for leg in get_adjacent():
            # Adjacent legs must not be moving or stepping
            if leg.is_moving or leg.is_stepping:
                return false
            # And have remained grounded for some time
            elif leg.time_since_grounded < step_crosspair_wait:
                return false

    # We can move and want to move!
    if not is_comfortable:
        if debug_enable and debug_step_reason:
            _debug_step_reason_text = DebugDraw.text(
                    step_target,
                    "Not comfortable%s!" % ('' if is_grounded else ' & floating'),
                    Color.DARK_ORANGE,
                    _debug_step_reason_text,
                    1.0
            )
        return true

    if not body.has_desired_forward:
        return false

    # Allow an early step if a paired leg recently started moving,
    # or all legs are ready to move and this one has enough distance to start the pair
    var all_grounded: bool = time_since_grounded >= step_delay
    for leg in get_diagonal():
        if leg.is_stepping and leg.time_since_stepped < step_pair_window:
            if debug_enable and debug_step_reason:
                _debug_step_reason_text = DebugDraw.text(
                        step_target,
                        "Stepping with %s!" % leg.name,
                        Color.DARK_ORANGE,
                        _debug_step_reason_text,
                        1.0
                )
            return true
        if all_grounded and leg.time_since_grounded < leg.step_delay:
            all_grounded = false
    # None of our diagonals have started to move, start the cycle!
    if all_grounded and dist_sqr >= early_step_distance * early_step_distance:
        if debug_enable and debug_step_reason:
            _debug_step_reason_text = DebugDraw.text(
                    step_target,
                    "Early step!",
                    Color.DARK_ORANGE,
                    _debug_step_reason_text,
                    1.0
            )
        return true

    return false

## Returns the legs ahead, behind, and across from this leg. These are the
## anti-paired legs.
func get_adjacent() -> Array[CrawlerLeg]:
    if cached_adjacent.size() > 0:
        return cached_adjacent

    var result: Array[CrawlerLeg]
    var max_id: int = body.legs.size()

    # Ahead
    var idx: int = index - 2
    if idx >= 0 and idx < max_id:
        result.append(body.legs[idx])

    # Behind
    idx = index + 2
    if idx >= 0 and idx < max_id:
        result.append(body.legs[idx])

    # Across
    if index % 2 == 0:
        idx = index + 1
    else:
        idx = index - 1

    if idx >= 0 and idx < max_id:
        result.append(body.legs[idx])

    return result

## Returns the legs diagonal to this leg. These are the paired legs.
func get_diagonal() -> Array[CrawlerLeg]:
    if cached_diagonal.size() > 0:
        return cached_diagonal

    var result: Array[CrawlerLeg]
    var max_id: int = body.legs.size()

    # Ahead
    var idx: int = index - 1
    if not is_left:
        idx -= 2
    if idx >= 0 and idx < max_id:
        result.append(body.legs[idx])

    # Behind
    idx = index + 1
    if is_left:
        idx += 2
    if idx >= 0 and idx < max_id:
        result.append(body.legs[idx])

    return result

## Returns the squared lateral distance to the target global rest.
func distance_squared_to_rest(coordinate: Vector3) -> float:
    return (coordinate - target_global_rest).slide(global_cast_direction).length_squared()
