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

## How much to swing the leg out while taking a step, 1.0 is 100% swing
@export_range(0.0, 1.0, 0.01, 'or_greater')
var leg_swing_amount: float = 0.0

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

## Transform used for moving step cast and rest point
var step_transform: Transform3D = Transform3D.IDENTITY

## Position of the leg at rest, set as the target position on setup
var target_rest_position: Vector3 = Vector3.INF
var target_global_rest: Vector3 = Vector3.INF
var target_last_global: Vector3 = Vector3.INF

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
var step_sweep_length: float
var current_step_distance: float
var next_step_target: Vector3 = Vector3.INF
var allow_step_sync: bool = false

var comfort_distance: float
var dist_sqr_to_rest: float

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
    comfort_distance = rest_distance

func _validate_property(property: Dictionary) -> void:
    if property.name == &'ground_bone':
        property.hint = PROPERTY_HINT_ENUM
        if body.skeleton:
            property.hint_string = body.skeleton.get_concatenated_bone_names()

func setup() -> void:
    if not has_initialized:
        has_initialized = true
        target_last_global = target.global_position
        target_rest_position = global_transform.inverse() * target.global_position
        attachment_point = (body.global_transform.inverse() * global_transform).origin

        var rest_vector: Vector3 = (body.global_transform.inverse() * target.global_position) - attachment_point
        step_sweep_length = PI * 0.5 * rest_vector.slide(Vector3.UP).length()

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
    ) * global_transform

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

func pre_update(state: PhysicsDirectBodyState3D) -> void:
    # time_since_moved += state.step
    time_since_stepped += state.step

    _update_grounded()

    if is_grounded:
        time_since_grounded += state.step

    _update_step_transform(state.transform.basis, state.step)

    _update_comfort_distance(state.step)

    _update_target_position(state.step)

    var local_rest: Vector3 = step_transform * target_rest_position
    target_global_rest = global_transform * local_rest

    var rest_delta: Vector3 = target.position - local_rest
    rest_delta.y = 0.0
    dist_sqr_to_rest = rest_delta.length_squared()
    is_comfortable = dist_sqr_to_rest <= comfort_distance * comfort_distance

    if debug_enable and debug_rest_area:
        var color: Color = Color.GREEN
        if not is_comfortable:
            color = Color.RED
        _debug_rest_circle = DebugDraw.circle(
                target_global_rest,
                comfort_distance,
                global_basis.y,
                16,
                color,
                _debug_rest_circle,
                1.0
        )

    _update_shape_cast(state.transform.basis)
    if shape_cast.is_colliding():
        next_step_target = shape_cast.get_collision_point(0) * global_transform

        if is_stepping:
            current_step_distance = minf(current_step_distance + (next_step_target - step_target).length(), 2.0 * step_distance)
            step_target = next_step_target

func _update_grounded() -> void:
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

func _update_step_transform(body_basis: Basis, step: float) -> void:
    var target_transform: Transform3D = Transform3D.IDENTITY
    if body.has_desired_forward:
        target_transform.origin += body_basis.inverse() * body.desired_direction * move_offset

        var is_front: bool = index < 2
        var is_back: bool = index + 2 >= body.legs.size()

        var cos_theta: float = body.desired_direction.dot(-body_basis.z)

        if is_front or is_back:
            cos_theta = absf(cos_theta) * 2.0 - 1.0
            if is_front:
                if is_left:
                    cos_theta *= -1.0
            elif not is_left:
                cos_theta *= -1.0
        elif is_left:
            cos_theta *= -1.0

        target_transform = target_transform.rotated_local(Vector3.UP, move_spin * cos_theta)

    if step_transform != target_transform:
        # Force at least 0.5cm of travel each interpolation
        # TODO: min travel should be delta'd, needs a multiply by state.step!!
        var min_weight: float = minf(2.5e-5 / step_transform.origin.distance_squared_to(target_transform.origin), 1.0)
        step_transform = step_transform.interpolate_with(target_transform, maxf(step * move_interp_rate, min_weight))

        if step_transform.is_equal_approx(target_transform):
            step_transform = target_transform

func _update_comfort_distance(step: float) -> void:
    if body.is_stepping:
        comfort_distance = move_toward(comfort_distance, step_distance, step * 2.0)
    elif step_transform.is_equal_approx(Transform3D.IDENTITY):
        # TODO: maybe always move comfort distance? Legs should handle moving targets now.
        comfort_distance = move_toward(comfort_distance, rest_distance, step * 2.0)

func _update_target_position(step: float) -> void:
    if is_stepping or is_moving:
        # Try to maintain current position at 1m/s
        target.position = target_bone_position.move_toward(target.position, step)
    elif is_grounded:
        # Try to maintain global position using deceleration
        var global_bone: Vector3 = global_transform * target_bone_position
        target.global_position = global_bone.move_toward(target_last_global, body.deceleration * step)
    else:
        target.position = target_bone_position

func _update_shape_cast(body_basis: Basis) -> void:

    # Rotate in direction of motion
    var old_shape_cast_xform: Transform3D = shape_cast.transform
    if body.has_desired_forward and not is_zero_approx(step_cast_angle):
        var rot_axis: Vector3 = body_basis.inverse() * body.desired_direction.cross(body_basis.y)
        rot_axis = rot_axis.normalized()
        var angle: float = step_cast_angle# * (1.0 - absf(state.transform.basis.tdoty(body.desired_direction)))
        var point: Vector3 = target_rest_position - shape_cast.position

        # NOTE: Think of making a "transform sandwich", order the lines as if you are looking at
        #       the side profile of a "transform sandwich".
        var xform: Transform3D = Transform3D.IDENTITY
        xform = xform.translated(-point)
        xform = xform.rotated(rot_axis, angle)
        xform = xform.translated(target_rest_position)

        shape_cast.transform = xform
    shape_cast.transform = step_transform * shape_cast.transform
    shape_cast.force_shapecast_update()

    if debug_enable and debug_step_cast:
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

    shape_cast.transform = old_shape_cast_xform

func check_early_step() -> void:
    allow_step_sync = false
    if not shape_cast.is_colliding():
        return

    # NOTE: The method call 'can_start_step' may enable 'allow_step_sync'
    if (not is_stepping) and can_start_step():
        start_step()

func update(state: PhysicsDirectBodyState3D) -> void:

    _update_step(state.step)

    #if index == 0:
        #print((target.global_position - target_last_global).length() / state.step)

    if debug_enable and debug_ik_target:
        _debug_ik_sphere = DebugDraw.sphere(
                target.global_position,
                0.02,
                Color.AQUA,
                _debug_ik_sphere
        )

    target_last_global = target.global_position

func _update_step(delta: float) -> void:
    if (not is_moving) and (not is_stepping) and shape_cast.is_colliding() and should_sync_step():
        start_step()

    if not is_stepping:
        if debug_enable and debug_step_target:
            _debug_target_sphere = DebugDraw.sphere(
                    Vector3.ZERO,
                    0.0,
                    Color.TRANSPARENT,
                    _debug_target_sphere,
                    0.0
            )
        return

    if debug_enable and debug_step_target:
        _debug_target_sphere = DebugDraw.sphere(
                global_transform * step_target,
                (shape_cast.shape as SphereShape3D).radius,
                Color.FIREBRICK * Color(1.0, 1.0, 1.0, 0.3),
                _debug_target_sphere,
                1.0
        )

    var leg_speed: float

    if body.has_desired_forward:
        leg_speed = body.desired_speed
    elif step_transform == Transform3D.IDENTITY:
        # At rest, use ground speed
        leg_speed = clampf(
                body.ground_direction.dot(body.ground_velocity),
                body.max_speed / 3.0,
                body.max_speed
        )
    else:
        # Use very small leg speed while interpolating to rest
        leg_speed = maxf(body.max_speed / 20.0, 0.05)

    var step_current: Vector3 = target.position
    var vertical: float = step_current.y
    step_current.y = 0.0

    var flat_target: Vector3 = step_target
    flat_target.y = 0.0

    if is_zero_approx(leg_swing_amount):
        step_current = step_current.move_toward(
            flat_target,
            delta * leg_speed * current_step_distance * 2.718
        )
    else:
        var angle: float = step_current.signed_angle_2(flat_target, Vector3.UP)
        if not is_zero_approx(angle):
            step_current = step_current.rotated(
                Vector3.UP,
                signf(angle) * minf(
                    absf(angle),
                    leg_speed / step_sweep_length
                    * PI * 0.5
                    * delta
                )
            )

        var current_length: float = step_current.length()
        if not is_zero_approx(current_length):
            step_current = step_current / current_length
            step_current *= move_toward(
                current_length,
                flat_target.length(),
                leg_speed * delta
            )

        if leg_swing_amount < 1.0:
            var normal: Vector3 = (flat_target - step_current).cross(Vector3.UP)
            if not normal.is_zero_approx():
                var linear_plane: Plane = Plane(normal.normalized(), flat_target)
                var linear_point: Vector3 = linear_plane.project(step_current)
                step_current = step_current.lerp(linear_point, 1.0 - leg_swing_amount)

    if step_current.is_equal_approx(flat_target):
        step_current.y = move_toward(
            vertical,
            step_target.y,
            leg_speed * delta
        )
    else:
        step_current.y = move_toward(
            vertical,
            step_target.y + leg_lift_height,
            leg_speed * delta
        )

    if step_current.distance_squared_to(step_target) < 1e-4:
        is_stepping = false
        target.position = step_target
    else:
        target.position = step_current

func start_step() -> void:
    is_stepping = true
    time_since_stepped = 0.0
    step_target = next_step_target
    current_step_distance = (step_target - target_bone_position).length()

func can_start_step() -> bool:
    # Must be not moving
    if is_moving:
        return false

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
                    target.global_position,
                    "Not comfortable%s!" % ('' if is_grounded else ' & floating'),
                    Color.DARK_ORANGE,
                    24.0,
                    _debug_step_reason_text,
                    1.0
            )
        return true

    if not body.has_desired_forward:
        return false

    # Allow an early step if all legs are ready to move and this one has enough
    # distance to start the pair
    if time_since_grounded < step_delay:
        return false

    allow_step_sync = true

    if dist_sqr_to_rest < early_step_distance * early_step_distance:
        return false

    for leg in get_diagonal():
        if leg.time_since_grounded < leg.step_delay:
            return false

    # None of our diagonals have started to move, start the cycle!
    if debug_enable and debug_step_reason:
        _debug_step_reason_text = DebugDraw.text(
                target.global_position,
                "Early step!",
                Color.DARK_ORANGE,
                24.0,
                _debug_step_reason_text,
                1.0
        )
    return true

## If this leg should start stepping because it can synchronize with another
## leg that has begun to step
func should_sync_step() -> bool:
    if not allow_step_sync:
        return false

    for leg in get_diagonal():
        if leg.is_stepping and leg.time_since_stepped < step_pair_window:
            if debug_enable and debug_step_reason:
                _debug_step_reason_text = DebugDraw.text(
                        target.global_position,
                        "Stepping with %s!" % leg.name,
                        Color.DARK_ORANGE,
                        24.0,
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
