@tool
class_name CrawlerLeg extends Node3D


## The node that IK uses for this leg
@export_custom(PROPERTY_HINT_NODE_TYPE, 'Marker3D', PROPERTY_USAGE_STORAGE)
var target: Marker3D

@export_custom(PROPERTY_HINT_ENUM, '')
var ground_bone: StringName

## Physical bone chain layout for this leg
@export var physical_bone_chain: PhysicalBoneChainResource:
    set = _set_physical_bone_chain

## Shareable general leg parameters
@export var setting: CrawlerLegSetting:
    set = set_setting

#region Debug
@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = true

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
@export var debug_ground_cast: bool = true
var _debug_ground_cast_vector: int = 0
var _debug_ground_cast_shape: int = 0

## Render text at the leg giving the reason it takes a step
@export var debug_step_reason: bool = false
var _debug_step_reason_text_id: int = 0
var _debug_step_reason_text: String
#endregion Debug

var body: CrawlerCharacter = null:
    set(value):
        body = value
        if physical_bone_chain:
            update_chain_setting()
        notify_property_list_changed()
var index: int = -1
var is_left: bool:
    get():
        return index % 2 == 0
## True when `is_grounded and (not is_stepping)`
var apply_ground_forces: bool:
    get():
        return is_grounded and (not is_stepping)
var has_initialized: bool = false

## Initial location of the leg position relative to the body
var attachment_point: Vector3 = Vector3.ZERO

## The floor step target raycast
var shape_cast: ShapeCast3D

## Transform used for moving step cast and rest point
var step_transform: Transform3D = Transform3D.IDENTITY

## Position of the leg at rest, set as the target position on setup
var target_rest_position: Vector3 = Vector3.INF
var target_global_rest: Vector3 = Vector3.INF
## Last global position of the leg target, used to track relative velocities
var target_last_global_position: Vector3 = Vector3.INF
## Contact velocity of this leg relative to the ground
var ground_rel_con_velocity: Vector3 = Vector3.ZERO

## The leg is currently touching ground
var is_grounded: bool = false
## How long it has been since the leg collided with ground
var time_since_grounded: float = 0.0
## If the leg had ground contact from the previous frame
var grounded_last_tick: bool = false

## The leg is currently in motion
var is_moving: bool = false
## How long it has been since the last movement began
var time_since_moved: float = 0.0

## The leg is currently taking a step
var is_stepping: bool = false
## How long it has been since the last step began
var time_since_start_step: float = 0.0
## How long it has been since the last step ended
var time_since_last_step: float = 0.0

## The leg is currently lifting up to avoid contact with the ground, and so it
## should likely be excluded from friction and ground normal calculations.
var is_lifting: bool = false
## The leg should be forced to remain lifted, excluding it from most motions
var force_lifting: bool = false

## The leg is in a comfortable position. This is used to signal that the leg
## wants to move to a better position.
var is_comfortable: bool = false

var allow_step_sync: bool = false
var current_step_travel: float
var next_step_target_global: Vector3 = Vector3.INF
var step_target_global: Vector3 = Vector3.INF
var step_target: Vector3 = Vector3.INF
var step_origin: Vector3 = Vector3.INF

var comfort_distance: float
var dist_sqr_to_rest: float
var leg_normal: Vector3 = Vector3.ZERO

var ground_bone_idx: int = -1
var ground_cast: ShapeCast3D
var ground_body: RID
var ground_normal: Vector3 = Vector3.INF
## Ground contact position in global space
var ground_point: Vector3 = Vector3.INF
## Velocity of the ground at the contact point
var ground_velocity: Vector3 = Vector3.ZERO
## Computed real velocity of the ground from tick-to-tick
var ground_last_velocity: Vector3 = Vector3.ZERO
var ground_xform: Transform3D = Transform3D.IDENTITY
var ground_friction: float = 0.0
## Set by the parent CrawlerCharacter class, exists here for (attempted) organization
var ground_offset: float = INF

var ground_last_rid: RID
var ground_last_local: Vector3

var target_bone_idx: int = -1

var cached_adjacent: Array[CrawlerLeg]
var cached_diagonal: Array[CrawlerLeg]
var cached_step: float


## Target step height
var step_height: float = 0.0

var use_new_leg_mode: bool = false


func _enter_tree() -> void:
    connect_setting()

func _exit_tree() -> void:
    disconnect_setting()

func _validate_property(property: Dictionary) -> void:
    if property.name == &'ground_bone':
        property.hint = PROPERTY_HINT_ENUM
        if body.skeleton:
            property.hint_string = body.skeleton.get_concatenated_bone_names()

func set_setting(new_setting: CrawlerLegSetting) -> void:
    if setting:
        disconnect_setting()
    setting = new_setting
    if setting:
        connect_setting()

func setup(cast_exceptions: Array[RID]) -> void:
    if has_initialized:
        return

    # Teleport to root bone position, is a method to share with CrawlerCharacter
    # build tool
    apply_position()
    # Setup target node and position, same reason as above
    setup_target()


    cached_adjacent = get_adjacent()
    cached_diagonal = get_diagonal()

    comfort_distance = setting.rest_distance
    target_rest_position = global_transform.inverse() * target.global_position
    attachment_point = (body.global_transform.inverse() * global_transform).origin


    ground_bone_idx = body.skeleton.find_bone(ground_bone)
    if ground_bone_idx == -1:
        push_error(
            'Unable to find ground bone "%s" for leg %s!' % [ground_bone, name]
        )
        return

    shape_cast = ShapeCast3D.new()
    shape_cast.name = 'StepCast'
    shape_cast.enabled = false # Manually update the cast
    add_child(shape_cast, false, Node.INTERNAL_MODE_FRONT)

    ground_cast = ShapeCast3D.new()
    ground_cast.name = 'GroundCast'
    ground_cast.enabled = false
    ground_cast.top_level = true
    add_child(ground_cast, false, Node.INTERNAL_MODE_FRONT)

    for rid in cast_exceptions:
        shape_cast.add_exception_rid(rid)
        ground_cast.add_exception_rid(rid)

    setting_modified()

    has_initialized = true

func apply_position() -> void:
    if not physical_bone_chain:
        return

    var bone_xform: Transform3D = body.skeleton.global_transform * body.skeleton.get_bone_global_pose(body.skeleton.find_bone(physical_bone_chain.root_bone))
    global_position = bone_xform.origin
    global_basis = Basis.IDENTITY

func setup_target() -> void:
    target_bone_idx = -1
    if physical_bone_chain:
        target_bone_idx = body.skeleton.find_bone(physical_bone_chain.end_bone)

    if target_bone_idx == -1:
        push_error(
            'Unable to find end bone targetting node "%s" for leg %s!' % [target.name, name]
        )
        return

    if not target:
        target = Marker3D.new()
        target.name = '%sTarget' % name
        add_child(target, true)
        target.owner = owner

    body.leg_ik.set_target_node(index, body.leg_ik.get_path_to(target))
    target.global_position = body.skeleton.global_transform * body.skeleton.get_bone_global_rest(target_bone_idx).origin
    target_last_global_position = target.global_position

func pose_updated() -> void:
    if use_new_leg_mode:
        _new_pose_updated()
        return

    leg_normal = (
              body.skeleton.global_transform
            * body.skeleton.get_bone_global_pose(body.skeleton.get_bone_parent(ground_bone_idx))
    ).basis.y

    # Render before copying the IK result
    if debug_enable and debug_ik_target:
        _draw_ik_target()

    target.global_position = (
              body.skeleton.global_transform
            * body.skeleton.get_bone_global_pose(target_bone_idx).origin
    )

func _new_pose_updated() -> void:
    pass

# TODO: This method needs to have a lot of stuff moved into the "update" method
#       instead, as this method does not know anything about the true leg
#       transforms because they haven't been updated yet
func pre_update(state: PhysicsDirectBodyState3D) -> void:
    if use_new_leg_mode:
        _new_pre_update(state)
        return

    cached_step = state.step

    if force_lifting:
        is_lifting = true

    # time_since_moved += state.step
    time_since_start_step += cached_step
    time_since_last_step += cached_step

    _update_grounded()

    if is_grounded:
        time_since_grounded += state.step

    _update_step_transform(state.transform.basis)

    # Run in pre-update to get ahead of the comfort distances
    if body.is_stepping:
        comfort_distance = move_toward(comfort_distance, setting.step_distance, cached_step * 2.0)

    var local_rest: Vector3 = step_transform * target_rest_position
    target_global_rest = global_transform * local_rest

    var rest_delta: Vector3 = target.position - local_rest
    rest_delta.y = 0.0
    dist_sqr_to_rest = rest_delta.length_squared()
    is_comfortable = dist_sqr_to_rest <= comfort_distance * comfort_distance

    if debug_enable and debug_rest_area:
        _draw_rest_area()

    _update_shape_cast(state.transform.basis)
    if shape_cast.is_colliding():
        next_step_target_global = shape_cast.get_collision_point(0)

        if is_stepping:
            step_target_global = next_step_target_global
            step_target = next_step_target_global * global_transform
    elif is_stepping:
        step_target = step_target_global * global_transform

func _new_pre_update(_state: PhysicsDirectBodyState3D) -> void:
    pass

func _update_grounded() -> void:
    var has_ground: bool = false

    var bone_parent_xform: Transform3D = body.skeleton.get_bone_global_pose(body.skeleton.get_bone_parent(ground_bone_idx))
    var target_position: Vector3 = body.skeleton.get_bone_global_pose(ground_bone_idx).origin
    var bone_direction: Vector3 = (target_position - bone_parent_xform.origin).normalized()
    var shape_size: float = (ground_cast.shape as SphereShape3D).radius
    var start_position: Vector3 = (bone_direction * (setting.ground_hit_start + shape_size))
    ground_cast.position = body.skeleton.global_transform * (target_position - start_position)
    ground_cast.basis = body.skeleton.global_basis * bone_parent_xform.basis
    ground_cast.target_position = Vector3.UP * (setting.ground_hit_start + setting.ground_hit_extra)

    ground_cast.force_shapecast_update()

    if debug_enable and debug_ground_cast:
        _draw_ground_cast()

    if ground_cast.is_colliding():
        ground_point = ground_cast.get_collision_point(0)
        ground_normal = ground_cast.get_collision_normal(0)

        var ground_cos_theta: float = ground_normal.dot(-leg_normal)
        if ground_cos_theta >= 0.0:
            has_ground = true

    if has_ground:
        if not is_grounded:
            is_grounded = true

        ground_body = ground_cast.get_collider_rid(0)
        var ground_state := PhysicsServer3D.body_get_direct_state(ground_body)
        ground_xform = ground_state.transform
        ground_velocity = ground_state.get_velocity_at_local_position(
                    ground_point - ground_state.transform.origin
                )
        ground_friction = PhysicsServer3D.body_get_param(ground_body, PhysicsServer3D.BODY_PARAM_FRICTION)

        if debug_enable and debug_ground_normal:
            _draw_ground_normal()

    elif is_grounded:
        is_grounded = false
        ground_normal = Vector3.INF
        ground_velocity = Vector3.ZERO
        ground_rel_con_velocity = Vector3.ZERO
        ground_friction = 0.0
        time_since_grounded = 0.0
        if debug_enable and debug_ground_normal:
            _draw_ground_normal(true)

func _update_step_transform(body_basis: Basis) -> void:
    var target_transform: Transform3D = Transform3D.IDENTITY
    if body.has_desired_forward:
        target_transform.origin += body_basis.inverse() * body.desired_direction * setting.move_offset

        var is_front: bool = index < 2
        var is_back: bool = index + 2 >= body.legs.size()

        var cos_theta: float = body.desired_direction.dot(-body_basis.z)

        if is_front:
            cos_theta = maxf(cos_theta * 2.0 - 1.0, -1.0)
        elif is_back:
            cos_theta = minf(cos_theta * 2.0 + 1.0, 1.0)

        if is_left:
            cos_theta *= -1.0

        target_transform = target_transform.rotated_local(Vector3.UP, setting.move_spin * cos_theta)

    if step_transform != target_transform:
        # Force at least 2cm/sec of travel each interpolation
        var min_weight: float = minf(2.0 * cached_step / step_transform.origin.distance_squared_to(target_transform.origin), 1.0)
        # TODO: improve interpolation by comparing the body's rel ground velocity to desired direction.
        #       Should interpolate only while it is positive, and reach max rate when at or beyond desired speed
        step_transform = step_transform.interpolate_with(target_transform, maxf(cached_step * setting.move_interp_rate * body.acceleration, min_weight))

        if step_transform.is_equal_approx(target_transform):
            step_transform = target_transform

func _update_shape_cast(body_basis: Basis) -> void:

    # Rotate in direction of motion
    var old_shape_cast_xform: Transform3D = shape_cast.transform
    if body.has_desired_forward and not is_zero_approx(setting.step_cast_angle):
        var rot_axis: Vector3 = body_basis.inverse() * body.desired_direction.cross(body_basis.y)
        rot_axis = rot_axis.normalized()
        var angle: float = setting.step_cast_angle# * (1.0 - absf(state.transform.basis.tdoty(body.desired_direction)))
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
        _draw_step_cast()

    shape_cast.transform = old_shape_cast_xform

func check_early_step() -> void:
    if use_new_leg_mode:
        return

    allow_step_sync = false
    if force_lifting or (not shape_cast.is_colliding()):
        return

    # NOTE: The method call 'can_start_step' may enable 'allow_step_sync'
    if (not is_stepping) and can_start_step():
        start_step()

func update() -> void:
    if use_new_leg_mode:
        _new_update()
        return
    _update_target()

    target_last_global_position = target.global_position

func _new_update() -> void:
    pass

func post_update() -> void:
    if use_new_leg_mode:
        _new_post_update()
        return

    if not body.is_stepping:
        var t: float = lerpf(setting.rest_distance, setting.step_distance, (body.ground_direction.dot(body.ground_velocity)) / body.max_speed)
        comfort_distance = move_toward(comfort_distance, t, cached_step * 2.0)

func _new_post_update() -> void:
    pass

func _update_target() -> void:
    # Prevent stepping when force lifting is enabled
    if force_lifting:
        is_stepping = false
        target.position.y = _calculate_lift(target.position.y, body.max_speed * cached_step)
        return

    if (
            (not is_moving)
        and (not is_stepping)
        and shape_cast.is_colliding()
        and should_sync_step()
    ):
        start_step()

    if not is_stepping:

        target.position.y = _calculate_lift(target.position.y, body.max_speed * cached_step)

        if debug_enable and debug_step_target:
            _draw_step_target(true)

        return

    if debug_enable:
        if debug_step_target:
            _draw_step_target()
        if debug_step_reason:
            _draw_step_reason()

    var leg_speed: float

    if body.has_desired_forward:
        leg_speed = body.desired_speed
    elif step_transform == Transform3D.IDENTITY:
        # At rest, use ground speed
        leg_speed = clampf(
                body.ground_direction.dot(body.ground_velocity),
                body.max_speed * 0.65,
                body.max_speed
        )
    else:
        # Use very small leg speed while interpolating to rest
        leg_speed = maxf(body.max_speed * 0.1, 0.05)

    # NOTE: In general, will be covering twice the comfort distance
    leg_speed *= maxf(comfort_distance * 2.0, 1.0)

    var step_current: Vector3 = target.position
    step_current.y = 0.0

    var step_goal: Vector3 = step_target
    step_goal.y = 0.0

    var current_dist: float = (step_goal - step_current).length()

    var step_delta: float = leg_speed * cached_step * clampf(current_dist / setting.step_distance, 1.0, 2.0)
    var new_step: Vector3 = _calculate_step_vector(step_current, step_goal, step_delta)

    current_dist = (step_goal - new_step).length()
    step_height = step_target.y + minf(setting.leg_lift_height, current_dist)

    if target.position.y < step_height:
        is_lifting = true
    else:
        is_lifting = false

    new_step.y = _calculate_lift(target.position.y, step_delta)

    # Fix to step delta
    var step_change: Vector3 = new_step - target.position
    new_step = target.position + step_change.limit_length(step_delta)

    if new_step.distance_squared_to(step_target) < 1e-4:
        is_stepping = false
        is_lifting = false
        time_since_last_step = 0.0
        target.position = step_target

        if debug_enable and debug_step_reason:
            _draw_step_reason(true)
    else:
        target.position = new_step

func _calculate_step_vector(current: Vector3, goal: Vector3, step_delta: float) -> Vector3:
    if is_zero_approx(setting.leg_swing_amount):
        return current.move_toward(goal, step_delta)

    var current_length_sqr: float = current.length_squared()
    var goal_length_sqr: float = goal.length_squared()

    # Check lengths
    if is_zero_approx(current_length_sqr) or is_zero_approx(goal_length_sqr):
        return current.move_toward(goal, step_delta)

    var radians: float = current.signed_angle_2(goal, Vector3.UP)

    # Check angle
    if is_zero_approx(radians) or is_zero_approx(absf(radians) - PI):
        return current.move_toward(goal, step_delta)

    var current_length: float = sqrt(current_length_sqr)
    var goal_length: float = sqrt(goal_length_sqr)

    radians = signf(radians) * minf( absf(radians), step_delta / current_length )
    var new_length: float = move_toward(current_length, goal_length, step_delta)

    var rotated_step = current.rotated(Vector3.UP, radians) * (new_length / current_length)

    if setting.leg_swing_amount < 1.0:
        var linear_point: Vector2 = Geometry2D.get_closest_point_to_segment(
                Vector2(rotated_step.x, rotated_step.z),
                Vector2(current.x, current.z),
                Vector2(goal.x, goal.z)
        )
        rotated_step = rotated_step.lerp(
                Vector3(linear_point.x, 0.0, linear_point.y),
                1.0 - setting.leg_swing_amount
        )

    # Fit to delta
    var travel: Vector3 = rotated_step - current
    rotated_step = current + travel.limit_length(step_delta)

    return rotated_step

func start_step() -> void:
    is_stepping = true
    is_lifting = true
    time_since_start_step = 0.0
    step_target_global = next_step_target_global
    step_target = step_target_global * global_transform
    step_origin = target.position

func _calculate_lift(current: float, delta: float) -> float:
    var baseline: float
    if is_stepping:
        baseline = step_height
    elif is_grounded:
        baseline = (ground_point * global_transform).y
    elif shape_cast.is_colliding():
        baseline = (next_step_target_global * global_transform).y
    else:
        baseline = target_rest_position.y

    if is_lifting:
        return move_toward(current, baseline + setting.leg_lift_height, delta)
    return move_toward(current, baseline, delta)

func can_start_step() -> bool:
    # Must be not moving
    if is_moving:
        return false

    if is_grounded:
        # Wait for this leg to remain in place before stepping again
        if time_since_last_step < setting.step_delay:
            return false

        for leg in get_adjacent():
            if leg.force_lifting:
                continue
            # Adjacent legs must not be moving or stepping
            if leg.is_moving or leg.is_stepping:
                return false
            # Ignore legs that are not grounding and not moving
            if not leg.apply_ground_forces:
                continue
            # And have remained grounded for some time, while applying ground forces
            if (not leg.apply_ground_forces) or leg.time_since_grounded < setting.step_crosspair_wait:
                return false

    # We can move and want to move!
    if not is_comfortable:
        if debug_enable and debug_step_reason:
            _debug_step_reason_text = "Not comfortable%s!" % ('' if is_grounded else ' & floating')
        return true

    # Step sync when the body is moving and this has remained grounded
    if not body.has_desired_forward:
        return false

    if (not is_grounded) or time_since_grounded < setting.step_delay:
        return false

    allow_step_sync = true

    # Allow an early step if all legs are ready to move and this one has enough
    # distance to start the pair
    if dist_sqr_to_rest < setting.early_step_distance * setting.early_step_distance:
        return false

    for leg in get_diagonal():
        if leg.force_lifting:
            continue
        if (not leg.apply_ground_forces) or leg.time_since_grounded < leg.setting.step_delay:
            return false

    # None of our diagonals have started to move, start the cycle!
    if debug_enable and debug_step_reason:
        _debug_step_reason_text = "Early step!"
    return true

## If this leg should start stepping because it can synchronize with another
## leg that has begun to step
func should_sync_step() -> bool:
    if not allow_step_sync:
        return false

    for leg in get_diagonal():
        if leg.is_stepping and leg.time_since_start_step < setting.step_pair_window:
            if debug_enable and debug_step_reason:
                _debug_step_reason_text = "Stepping with %s!" % leg.name
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

## Callback for preparing custom joints and their resources, mainly to apply
## resource changes onto the joint. Return false to signal an error.
func prepare_custom_joint(
        _joint: Joint3D,
        _joint_resource: Resource,
) -> bool:
    return true

## Callback for building custom joints. This should set the transform of the
## joint before returning it, which will be used as a local transform from the
## bone in global pose space. Returning null will be interpreted as an error.
func build_custom_joint(
        _chain: PhysicalBoneChain3D,
        part: PhysicalBonePart3D,
        main_body: RigidBody3D,
        parent_body: RigidBody3D,
        joint_resource: Resource,
) -> Joint3D:
    # For now, this is the only custom joint type we make
    var beam_res := joint_resource as BeamPivotJoint3DSetting
    if not beam_res:
        return null

    var beam_joint := BeamPivotJoint3D.new()
    beam_joint.set_meta(&'_custom_type_script', ResourceUID.id_to_text(ResourceLoader.get_resource_uid((beam_joint.get_script() as Script).resource_path)))
    beam_joint.setting = beam_res
    beam_joint.name = beam_joint.setting.resource_name

    if beam_res.attach_to_main_body:
        beam_joint.node_a = main_body.get_path()
        beam_joint.body_A_offset = main_body.global_transform.affine_inverse() * global_position
    else:
        beam_joint.node_a = parent_body.get_path()

    beam_joint.node_b = part.get_path()

    return beam_joint

func _set_physical_bone_chain(new_chain: PhysicalBoneChainResource) -> void:
    physical_bone_chain = new_chain

    if not physical_bone_chain:
        return

    update_chain_setting()

func update_chain_setting() -> void:
    if (not body) or (not body.skeleton):
        return

    physical_bone_chain.callable_get_bone_name = body.skeleton.get_bone_name
    physical_bone_chain.callable_get_bone_name_hint = body.skeleton.get_concatenated_bone_names
    physical_bone_chain.refresh_part_list_bone_names()

func connect_setting() -> void:
    if setting.changed.is_connected(setting_modified):
        return
    setting.changed.connect(setting_modified)

func disconnect_setting() -> void:
    if not setting.changed.is_connected(setting_modified):
        return
    setting.changed.disconnect(setting_modified)

func setting_modified() -> void:
    ground_cast.collision_mask = setting.ground_collision_mask
    ground_cast.shape = setting.ground_cast_shape

    shape_cast.collision_mask = setting.step_cast_collision_mask
    shape_cast.shape = setting.step_cast_shape
    shape_cast.target_position = Vector3.UP * (setting.step_cast_end - setting.step_cast_start)
    shape_cast.global_position = body.skeleton.global_transform * body.skeleton.get_bone_global_rest(target_bone_idx).origin
    shape_cast.position += Vector3.UP * setting.step_cast_start

func _draw_step_cast() -> void:
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

func _draw_step_target(clear: bool = false) -> void:
    if clear:
        _debug_target_sphere = DebugDraw.sphere(
                Vector3.ZERO,
                0.0,
                Color.TRANSPARENT,
                _debug_target_sphere,
                0.0
        )
        return
    _debug_target_sphere = DebugDraw.sphere(
            global_transform * step_target,
            (shape_cast.shape as SphereShape3D).radius,
            Color.FIREBRICK * Color(1.0, 1.0, 1.0, 0.3),
            _debug_target_sphere,
            1.0
    )

func _draw_step_reason(clear: bool = false) -> void:
    if clear:
        _debug_step_reason_text_id = DebugDraw.text(
                Vector3.INF,
                '',
                Color.DARK_ORANGE,
                16.0,
                _debug_step_reason_text_id,
                0.1
        )
        return
    _debug_step_reason_text_id = DebugDraw.text(
            target.global_position,
            _debug_step_reason_text,
            Color.DARK_ORANGE,
            24.0,
            _debug_step_reason_text_id,
            1.0
    )

func _draw_ik_target() -> void:
    _debug_ik_sphere = DebugDraw.sphere(
            target.global_position,
            0.02,
            Color.AQUA,
            _debug_ik_sphere
    )

func _draw_ground_cast() -> void:
    var shape_origin: Vector3 = ground_cast.target_position
    var shape_color: Color
    if ground_cast.is_colliding():
        shape_origin *= ground_cast.get_closest_collision_safe_fraction()
        shape_color = Color.DARK_ORCHID
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

func _draw_ground_normal(clear: bool = false) -> void:
    if clear:
        _debug_ground_normal_vector = DebugDraw.vector(
                Vector3.ZERO,
                Vector3.ZERO,
                Color.CORNFLOWER_BLUE,
                _debug_ground_normal_vector,
                0.001
        )
        return
    _debug_ground_normal_vector = DebugDraw.vector(
            ground_point,
            ground_normal * 0.5,
            Color.CORNFLOWER_BLUE,
            _debug_ground_normal_vector
    )

func _draw_rest_area() -> void:
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
