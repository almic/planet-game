@tool
class_name CrawlerLeg extends Node3D


## The node that IK uses for this leg, using local-space positions
@export_custom(PROPERTY_HINT_NODE_TYPE, 'Marker3D')
var target: Marker3D

@export_tool_button('Reset Target', '3D')
@warning_ignore("unused_private_class_variable")
var _btn_editor_reset_target = editor_reset_target

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

## Render text at the leg giving the reason it takes a step
@export var debug_move_reason: bool = false
var _debug_move_reason_text_id: int = 0
var _debug_move_reason_text: String
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
var is_leader: bool:
    get():
        return sync_paired.size() > 0 and sync_paired[0].index == index
var has_initialized: bool = false

## Initial location of the leg position relative to the body
var attachment_point: Vector3 = Vector3.ZERO

## The floor step target raycast
var step_cast: ShapeCast3D

## Rest point of the step cast
var step_cast_rest_position: Vector3
## Transform that controls leg rotation and directional movement offset for the step cast
var step_transform: Transform3D = Transform3D.IDENTITY

## Initial rest position of the leg, set as the target position on setup.
var rest_position: Vector3 = Vector3.INF
## Contact velocity of this leg
var contact_velocity: Vector3 = Vector3.ZERO
## Contact velocity of this leg relative to the ground
var ground_rel_con_velocity: Vector3 = Vector3.ZERO

## The leg is currently touching ground
var is_grounded: bool = false
## How long it has been since the leg collided with ground
var time_since_grounded: float = 0.0
## If the leg had ground contact from the previous frame
var grounded_last_tick: bool = false

## The leg is currently in motion
var is_moving: bool:
    get():
        return is_stepping or is_recovering or target_point_index != -1
## How long it has been since the last movement began
var time_since_moved: float = 0.0

## The leg is currently taking a step
var is_stepping: bool = false
## How long it has been since the last step began
var time_since_start_step: float = 0.0
## How long it has been since the last step ended
var time_since_last_step: float = 0.0

## When is_stepping is true, the leg is attempting to return to last known
## ground point. When is_stepping is false, the leg is assuming a reasonable
## position that might be close to ground.
var is_recovering: bool = false

## The leg is in a comfortable position. This is used to signal that the leg
## wants to move to a better position.
var is_comfortable: bool = false

## There is no current target
var is_without_target: bool:
    get():
        return target_point_index == -1

## Controlled by the owning body, helper field to track broken legs
var is_broken: bool = false


var comfort_distance: float
var dist_sqr_to_rest: float
## Global space leg normal vector
var normal: Vector3
## Local space position of the end of the leg
var local_end_point: Vector3
## Global space position of the end of the leg
var global_end_point: Vector3 = Vector3.INF

## Decided by this leg. These are legs that this leg generally should not move with.
var cross_paired: Array[CrawlerLeg]
## Provided by main body. These are legs that this leg generally should move with.
var sync_paired: Array[CrawlerLeg]

## Most recent global step target from the step cast
var next_step_target_global: Vector3 = Vector3.INF
## There is a next step target available
var has_next_step_target: bool:
    get():
        return next_step_target_global.is_finite()
## During steps, this is used to prevent the final target from moving too far
## from the original target.
var step_target_initial: Vector3
## During steps, this is updated for orientation prediction of the main body
var step_target_current: Vector3

## When in motion, these are the targets for the leg. The W component encodes
## the goal distance, and when negative marks the point as global space.
var target_point_list: PackedVector4Array
## Extra data for target points. 0 encodes the delay upon reaching the goal.
var target_point_data_list: PackedFloat32Array
var target_point_index: int = -1
var target_point_index_ik_checked: int = -1
## If the target can skip ahead to future points that are closer. Disable this
## for movements that have repeated positions, like a wave.
var target_allow_skipping_ahead: bool = false
## If the end target point is ground and target should try waiting until ground
## is reached instead of ending as soon as the goal distance is met.
var target_wait_for_ground: bool = false
## Current target rest in local space, the leg will continuously travel to this
## point when it has no other target points. When displaced, this target is
## moved towards the displacement at a set rate.
var target_rest_position: Vector3

## Flags provided during target setup, controls how targeting works
enum TargetFlags {
    ALLOW_SKIPPING = 1,
    WAIT_FOR_GROUND = 2
}

#region Ground Stuff
var ground_bone_idx: int = -1
var ground_cast: SpringCast
## The body used to calculate ground relative contact velocity
var ground_physical_part: PhysicalBonePart3D
## Length of the ground bone, used to calculate the leg end position
var ground_bone_length: float = 0.0
## Ground contact normal in global space
var ground_normal: Vector3 = Vector3.INF
## Ground contact position in global space
var ground_position: Vector3 = Vector3.INF
## Velocity of the ground at the contact point
var ground_contact_velocity: Vector3 = Vector3.ZERO
## Total friction force applied
var ground_friction: Vector3

var ground_last_rid: RID
var ground_last_local: Vector3
#endregion Ground Stuff

## Bone of the end point of the leg, where the target is compared to
var target_bone_idx: int = -1


func editor_reset_target() -> void:
    if target_bone_idx == -1 and physical_bone_chain:
        target_bone_idx = body.skeleton.find_bone(physical_bone_chain.end_bone)
    target.global_position = body.skeleton.global_transform * body.skeleton.get_bone_global_rest(target_bone_idx).origin

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

func setup(cast_exceptions: Array[RID], sync_with: Array[CrawlerLeg]) -> void:
    if has_initialized:
        return

    # Teleport to root bone position, is a method to share with CrawlerCharacter
    # build tool
    apply_position()

    # Setup target node and position, same reason as above
    setup_target()

    # Cache leg pairs
    cross_paired = get_cross_paired_legs()
    sync_paired = sync_with

    comfort_distance = setting.rest_distance
    rest_position = target.position
    target_rest_position = target.position
    local_end_point = target.position
    attachment_point = body.to_local(global_position)
    step_cast_rest_position = transform.affine_inverse() * body.skeleton.get_bone_global_rest(target_bone_idx).origin
    ground_bone_length = body.skeleton.get_bone_rest(target_bone_idx).origin.length()

    ground_bone_idx = body.skeleton.find_bone(ground_bone)
    if ground_bone_idx == -1:
        push_error(
            'Unable to find ground bone "%s" for leg %s!' % [ground_bone, name]
        )
        return

    ground_physical_part = body.physical_skeleton.get_bone_part_map().get(body.skeleton.get_bone_parent(ground_bone_idx)) as PhysicalBonePart3D
    if ground_physical_part == null:
        push_error(
            'Unable to get ground physical part from bone "%s" (index %d) for leg %s!' % [ground_bone, ground_bone_idx, name]
        )
        return

    step_cast = ShapeCast3D.new()
    step_cast.name = 'StepCast'
    step_cast.enabled = false # Manually update the cast
    add_child(step_cast, false, Node.INTERNAL_MODE_FRONT)
    step_cast.position = step_cast_rest_position
    step_cast.position.y += setting.step_cast_start

    ground_cast = SpringCast.new()
    ground_cast.name = 'GroundCast'
    ground_cast.settings = setting.ground_spring_setting
    ground_cast.collision_mask = setting.ground_collision_mask
    ground_physical_part.add_child(ground_cast, false, Node.INTERNAL_MODE_FRONT)
    ground_cast.main_body = ground_cast.get_path_to(ground_physical_part)

    for rid in cast_exceptions:
        step_cast.add_exception_rid(rid)
        # ground_cast.add_exception_rid(rid)

    setting_modified()

    has_initialized = true

func apply_position() -> void:
    if not physical_bone_chain:
        return

    var root_bone: int = body.skeleton.find_bone(physical_bone_chain.root_bone)
    global_position = body.skeleton.to_global(body.skeleton.get_bone_global_pose(root_bone).origin)
    basis = Basis.IDENTITY

func setup_target() -> void:
    target_bone_idx = -1
    if physical_bone_chain:
        target_bone_idx = body.skeleton.find_bone(physical_bone_chain.end_bone)

    if target_bone_idx == -1:
        push_error(
            'Unable to find end bone targeting node "%s" for leg %s!' % [target.name, name]
        )
        return

    if (not target) or (not target.is_inside_tree()):
        target = Marker3D.new()
        target.name = '%sTarget' % name
        target.gizmo_extents = 0.1
        add_child(target, true)
        target.owner = owner

    target.global_position = body.skeleton.to_global(body.skeleton.get_bone_global_rest(target_bone_idx).origin)
    body.leg_ik.setting_list[index].target_node = body.leg_ik.get_path_to(target)

    if Engine.is_editor_hint():
        return

    if not body.leg_ik.modification_processed.is_connected(on_ik_updated):
        body.leg_ik.modification_processed.connect(on_ik_updated)

## Watches IK to check for targeting failures, where IK is unable to reach the
## current target position and needs to be reset.
func on_ik_updated() -> void:
    const SOFT_RATE: float = 0.5

    # Need to verify that IK endpoint is within the current target distance,
    # otherwise it's a bug and devs should be notified with an error

    if not body.leg_ik.has_reached_goal(index):
        if body.leg_ik.has_made_progress(index):
            return

        # This can imply flickering or an impossible location
        if is_without_target:
            # Move rest towards current bone
            @warning_ignore("confusable_local_declaration")
            var local_bone: Vector3 = to_local(
                    body.skeleton.to_global(
                        body.skeleton.get_bone_global_pose(target_bone_idx).origin
                    )
            )
            target_rest_position = target_rest_position.lerp(local_bone, SOFT_RATE * body.delta_time)
        else:
            # Skip this target completely
            # TODO: use a delay instead of giving up instantly!
            target_point_index += 1
            if target_point_index >= target_point_list.size():
                @warning_ignore("confusable_local_declaration")
                var local_bone: Vector3 = to_local(
                        body.skeleton.to_global(
                            body.skeleton.get_bone_global_pose(target_bone_idx).origin
                        )
                )
                _on_target_finished(local_bone)

        return

    # Reached the goal, resting, do nothing
    if is_without_target:
        return

    # If we have already checked this index, we should not have to check it again
    if target_point_index_ik_checked == target_point_index:
        return
    target_point_index_ik_checked = target_point_index

    # Check that goal is close enough to current target point
    var target_point: Vector4 = target_point_list[target_point_index]
    var local_point: Vector3 = Vector3(target_point.x, target_point.y, target_point.z)
    if target_point.w < 0.0:
        local_point = to_local(local_point)
    var local_bone: Vector3 = to_local(
            body.skeleton.to_global(
                body.skeleton.get_bone_global_pose(target_bone_idx).origin
            )
    )
    var goal_dist_sqr: float = local_point.distance_squared_to(local_bone)
    if goal_dist_sqr < absf(target_point.w * target_point.w):
        return

    push_warning(
        (
            'Leg %d of %s has completed IK, but is not within %.3fm of '
            + 'target point %d. Please increase the target goal '
            + 'distance, or decrease the IK min_distance! Now!!!!'
        ) % [index, body.name, absf(target_point.w), target_point_index]
    )

    # TODO: remove this breakpoint later
    breakpoint

    local_point = local_bone
    if target_point.w < 0.0:
        local_point = to_global(local_point)
    target_point_list[target_point_index] = Vector4(local_point.x, local_point.y, local_point.z, target_point.w)

## Physics
func on_physics_update() -> void:
    normal = ground_physical_part.global_basis.y
    global_end_point = ground_physical_part.global_transform.translated_local(Vector3.UP * ground_bone_length).origin
    local_end_point = to_local(global_end_point)

    _update_grounded()
    _update_timers()
    _update_step_cast()

    if step_cast.is_colliding():
        next_step_target_global = step_cast.get_collision_point(0)

    # NOTE: With desired rotation, this could lag by a frame. This is acceptable to me.
    if body.has_desired_movement:
        comfort_distance = move_toward(comfort_distance, setting.step_distance, body.delta_time * 2.0)
    else:
        # NOTE: deliberately using last frame's body ground vectors
        var t: float = lerpf(setting.rest_distance, setting.step_distance, body.ground_speed / body.max_speed)
        comfort_distance = move_toward(comfort_distance, t, body.delta_time * 2.0)

    var local_rest: Vector3 = step_transform * rest_position

    var rest_delta: Vector3 = local_end_point - local_rest
    rest_delta.y = 0.0
    dist_sqr_to_rest = rest_delta.length_squared()
    is_comfortable = dist_sqr_to_rest <= comfort_distance * comfort_distance

    if debug_enable and debug_rest_area:
        _draw_rest_area()

func _update_grounded() -> void:
    # NOTE: when the ground is a static body, use this relative mass instead for ground velocity distribution
    const STATIC_MASS: float = 10000.0

    ground_position = Vector3.ZERO
    ground_normal = Vector3.INF
    ground_friction = Vector3.ZERO
    ground_contact_velocity = Vector3.ZERO
    ground_rel_con_velocity = Vector3.ZERO
    contact_velocity = Vector3.ZERO

    if ground_cast.is_colliding():
        ground_position = ground_cast.get_contact_average_point(0)
        var contact_normal: Vector3 = ground_cast.get_contact_normal(0)

        ground_normal = -contact_normal
        if debug_enable and debug_ground_normal:
            _draw_ground_normal()

        var ground_cos_theta: float = contact_normal.dot(normal)
        if ground_cos_theta >= 0.0:
            is_grounded = true

    elif is_grounded:
        is_grounded = false
        time_since_grounded = 0.0
        if debug_enable and debug_ground_normal:
            _draw_ground_normal(true)

    if not is_grounded:
        return

    var total_mass: float = 0.0

    for i in range(ground_cast.get_contact_body_count()):
        var ground_rid: RID = ground_cast.get_contact_body_rid(i)
        var ground_mass: float
        if PhysicsServer3D.body_get_mode(ground_rid) == PhysicsServer3D.BODY_MODE_STATIC:
            ground_mass = STATIC_MASS
        else:
            ground_mass = PhysicsServer3D.body_get_param(ground_rid, PhysicsServer3D.BODY_PARAM_MASS)

        total_mass += ground_mass
        ground_friction += ground_cast.get_contact_friction(i)

    var part_state := PhysicsServer3D.body_get_direct_state(ground_physical_part.get_rid())
    contact_velocity = part_state.get_velocity_at_local_position(ground_position - part_state.transform.origin)

    for i in range(ground_cast.get_contact_body_count()):
        var ground_rid: RID = ground_cast.get_contact_body_rid(i)
        var hit_position: Vector3 = ground_cast.get_contact_average_point(i)
        var ground_state := PhysicsServer3D.body_get_direct_state(ground_rid)
        var ground_velocity: Vector3
        var ground_mass: float
        if PhysicsServer3D.body_get_mode(ground_rid) == PhysicsServer3D.BODY_MODE_STATIC:
            ground_mass = STATIC_MASS
            ground_velocity = Vector3.ZERO
        else:
            ground_mass = PhysicsServer3D.body_get_param(ground_rid, PhysicsServer3D.BODY_PARAM_MASS)
            ground_velocity = ground_state.get_velocity_at_local_position(hit_position - ground_state.transform.origin)

        # Ground velocity contribution shared by mass proportion, higher mass contribute more
        var ratio: float = ground_mass / total_mass
        ground_rel_con_velocity += ratio * (contact_velocity - ground_velocity)
        ground_contact_velocity += ratio * ground_velocity

func _update_timers() -> void:
    # time_since_moved += body.delta_time
    time_since_start_step += body.delta_time
    time_since_last_step += body.delta_time

    if is_grounded:
        time_since_grounded += body.delta_time

func _update_step_cast() -> void:
    var target_transform: Transform3D = Transform3D.IDENTITY

    if body.has_desired_forward:
        target_transform.origin = (body.phys_state.transform.basis.inverse() * body.desired_direction) * setting.move_offset
        target_transform.origin.y = 0.0

        var is_front: bool = index < 2
        var is_back: bool = index + 2 >= body.legs.size()

        var cos_theta: float = body.desired_direction.dot(-body.phys_state.transform.basis.z)

        if is_front:
            cos_theta = cos_theta * 2.0 - 1.0
        elif is_back:
            cos_theta = cos_theta * 2.0 + 1.0

        if is_left:
            cos_theta *= -1.0

        cos_theta = clampf(cos_theta, -1.0, 1.0)
        target_transform = target_transform.rotated_local(Vector3.UP, setting.move_spin * cos_theta)

    if step_transform != target_transform:
        # Force at least 2cm/sec of travel each interpolation
        var min_weight: float = minf(2.0 * body.delta_time / step_transform.origin.distance_squared_to(target_transform.origin), 1.0)
        # TODO: improve interpolation by comparing the body's rel ground velocity to desired direction.
        #       Should interpolate only while it is positive, and reach max rate when at or beyond desired speed
        step_transform = step_transform.interpolate_with(target_transform, maxf(body.delta_time * setting.move_interp_rate * body.acceleration, min_weight))

        if step_transform.is_equal_approx(target_transform):
            step_transform = target_transform

    # Local step cast rotation and translation
    step_cast.transform = Transform3D.IDENTITY.translated(step_cast_rest_position)
    if body.has_desired_forward and not is_zero_approx(setting.step_cast_angle):
        var rot_axis: Vector3 = (
                  body.phys_state.transform.basis.inverse()
                * body.desired_direction.cross(body.phys_state.transform.basis.y)
        ).normalized()

        var angle: float = setting.step_cast_angle# * (1.0 - absf(state.transform.basis.tdoty(body.desired_direction)))

        step_cast.transform = step_cast.transform.rotated(rot_axis, angle)

    step_cast.transform = step_cast.transform.translated_local(Vector3.UP * setting.step_cast_start)
    step_cast.transform = step_transform * step_cast.transform

    step_cast.force_shapecast_update()

    if debug_enable and debug_step_cast:
        _draw_step_cast()

func update() -> void:
    # Only the leader checks leg
    if is_leader:
        var all_allowed: bool = true
        var early_step_leg: CrawlerLeg = null
        for leg in sync_paired:
            # This leg is already doing something
            if leg.is_moving:
                continue

            # Leg is doing nothing and without ground, it must recover ground
            if not leg.is_grounded:
                #leg.do_recover()
                #if leg.debug_enable and leg.debug_move_reason:
                #    leg._debug_move_reason_text = "Recovering, not moving and no ground!"
                continue

            # This leg has no step target, it cannot step right now
            if not leg.has_next_step_target:
                continue

            if not leg._can_move():
                all_allowed = false
                continue

            if not leg.is_comfortable:
                leg.do_step()
                if leg.debug_enable and leg.debug_move_reason:
                    leg._debug_move_reason_text = "Not comfortable%s!" % ('' if is_grounded else ' & floating')
                continue

            # Allow an early step if body has a forward and if any leg has
            # enough distance to start the group
            if (
                    early_step_leg != null
                    or (not body.has_desired_forward)
                    or leg.dist_sqr_to_rest < leg.setting.early_step_distance * leg.setting.early_step_distance
            ):
                continue
            early_step_leg = leg

        # Start remaining legs with an early step
        if all_allowed and early_step_leg != null:
            for leg in sync_paired:
                if leg.is_moving or not leg.has_next_step_target:
                    continue
                leg.do_step()
                if leg.debug_enable and leg.debug_move_reason:
                    if leg == early_step_leg:
                        leg._debug_move_reason_text = "Early step!"
                    else:
                        leg._debug_move_reason_text = "Stepping with %s!" % leg.name

    _update_target()

## Check this and cross-paired legs state to see if this leg is allowed to move,
## assuming it is currently stable. Unstable legs should always try to move.
func _can_move() -> bool:
    if time_since_last_step < setting.step_delay:
        return false

    for leg in cross_paired:
        if leg.is_moving:
            return false
        if not leg.is_grounded:
            continue
        if leg.time_since_grounded < setting.step_crosspair_wait:
            return false

    return true

## Start recovering from losing ground contact
func do_recover() -> void:
    is_recovering = true

    if ground_last_rid.is_valid() and ground_last_local.is_finite():
        # Obtain current world coordinate of the contact point, which could move
        # as if on a rotating/ translating platform
        var ground_state := PhysicsServer3D.body_get_direct_state(ground_last_rid)
        var ground_point: Vector3 = ground_state.transform * ground_last_local

        # Must be near enough to the leg right now
        var dist_sqr: float = global_end_point.distance_squared_to(ground_point)
        # TODO: parameter for max recover distance
        if dist_sqr <= 0.09: # NOTE: 30cm
            _prepare_for_target(TargetFlags.WAIT_FOR_GROUND)

            target_point_list.append(
                Vector4(ground_point.x, ground_point.y, ground_point.z, -0.08)
            )

    # 1. Try to return to the last ground contact point, using local space
    # 2. Draw a line from current end position to "safe" location, move target
    #    point a configured distance along that line.
    # 3. When ground is detected, recovery is complete, and a step is now
    #    possible to return to a comfortable position
    pass

## Start a movement to the most recent step cast target
func do_step() -> void:
    step_target_initial = next_step_target_global
    step_target_current = step_target_initial

    # Sometimes this leg is already very close, so just update the rest position
    # and don't count this as a real step
    var local_step_target: Vector3 = to_local(step_target_initial)
    if local_step_target.distance_squared_to(local_end_point) < 2.5e-3:
        target_rest_position = local_step_target
        return

    is_stepping = true
    time_since_start_step = 0.0
    _prepare_for_target(TargetFlags.ALLOW_SKIPPING | TargetFlags.WAIT_FOR_GROUND)

    var start_length: float = local_end_point.length()
    var end_length: float = local_step_target.length()
    var start_normalized: Vector3 = local_end_point.normalized()
    var end_normalized: Vector3 = local_step_target.normalized()
    var sweep_axis: Vector3 = local_end_point.cross(local_step_target).normalized()
    var angle: float = acos(start_normalized.dot(end_normalized))

    var use_rotation: bool = not (
               is_zero_approx(setting.leg_swing_amount)
            or is_zero_approx(start_length)
            or is_zero_approx(end_length)
            or is_zero_approx(angle)
            or sweep_axis.is_zero_approx()
    )

    # TODO: parameter for point count
    const POINTS: int = 4
    for i in range(1, POINTS + 2):
        var point: Vector3
        var is_global: bool = false
        if i == POINTS + 1:
            point = local_step_target
            is_global = true
        else:
            var progress: float = float(i) / float(POINTS)
            point = local_end_point.lerp(local_step_target, progress)
            if use_rotation:
                var rotated_point: Vector3 = start_normalized.rotated(sweep_axis, angle * progress)
                rotated_point *= ((1.0 - progress) * start_length) + (progress * end_length)
                point = point.lerp(rotated_point, setting.leg_swing_amount)
            # TODO: parameter for lift height curve
            point += Vector3.UP * minf(setting.leg_lift_height, setting.leg_lift_height * 2.0 * progress)

        # TODO: parameter for target distance
        var point_4: Vector4 = Vector4(point.x, point.y, point.z, 0.08)
        if is_global:
            point_4.w = -point_4.w

        target_point_list.append(point_4)

## Clears target list, resets flags and indices. Skipping requires the target
## list to have the current position first, so this will automatically add it.
func _prepare_for_target(flags: int = 0) -> void:
    target_point_list.clear()
    target_point_data_list.clear()
    target_allow_skipping_ahead = flags & TargetFlags.ALLOW_SKIPPING
    target_wait_for_ground = flags & TargetFlags.WAIT_FOR_GROUND

    if target_allow_skipping_ahead:
        target_point_index = 1
        var c: Vector3 = global_end_point
        target_point_list.append(Vector4(c.x, c.y, c.z, -1.0))
    else:
        target_point_index = 0
    target_point_index_ik_checked = -1

func _update_target() -> void:

    if debug_enable and debug_step_target and is_stepping:
        _draw_step_target()

    if debug_enable and debug_move_reason and is_moving:
        _draw_move_reason()

    if is_without_target:
        if is_recovering:
            # Recovering without ground, use safe location
            _update_recovery_target()
        else:
            # At rest, travel towards leg end point
            _update_target_rest()

        if debug_enable and debug_ik_target:
            _draw_ik_target()

        return

    # Motion is a step, and we got a new step target, update final goal point
    if is_stepping and time_since_start_step > 0.0 and step_cast.is_colliding():
        # Only update if new point is locally close to current target, otherwise
        # it will mess up the movement and we should just wait to make a new step
        var last: int = target_point_list.size() - 1
        var step_target: Vector4 = target_point_list[last]
        var max_travel: float = absf(step_target.w)
        var new_point: Vector3 = step_target_initial.move_toward(next_step_target_global, max_travel)
        step_target_current = new_point
        target_point_list[last] = Vector4(new_point.x, new_point.y, new_point.z, step_target.w)

    # Moving through targets, check distances and update target
    var target_point: Vector4 = target_point_list[target_point_index]
    var local_target_point: Vector3 = Vector3(target_point.x, target_point.y, target_point.z)
    if target_point.w < 0.0:
        local_target_point = to_local(local_target_point)

    # TODO: Add timer delays using target_data[index * span + 0] value.
    #       Probably flip a bool to use the above resting code but with a more
    #       aggressive holding (don't move the rest target point?), or reset the
    #       timer if too far? idk.

    var dist_sqr: float = local_end_point.distance_squared_to(local_target_point)
    if dist_sqr <= absf(target_point.w * target_point.w):
        if _should_wait_for_ground():
            if debug_enable and debug_ik_target:
                _draw_ik_target()
            return

        target_point_index += 1
        if target_point_index >= target_point_list.size():
            _on_target_finished(local_target_point)
            return

    if not target_allow_skipping_ahead:
        target.position = local_target_point

        if debug_enable and debug_ik_target:
            _draw_ik_target()

        return

    # 1. Compare current travel direction to A->B direction, if zero or less:
    # 2. Compare distance to current target and future, if future is closer,
    #    skip ahead. Otherwise:
    # 3. Compare dot products of here to B, and here to C, select the target
    #    with the higher result.
    # 4. Repeat until no skip is made.
    while true:
        local_target_point = _get_target_point(target_point_index)
        if target_point_index + 1 >= target_point_list.size():
            break

        var current_travel_dir: Vector3 = local_end_point.direction_to(local_target_point)
        # NOTE: always safe, index starts at 1, first point is initial position
        var prev_target: Vector3 = _get_target_point(target_point_index - 1)
        var original_travel_dir: Vector3 = prev_target.direction_to(local_target_point)

        if current_travel_dir.dot(original_travel_dir) > 0.0:
            break # Same direction, keep going towards target

        var next_target: Vector3 = _get_target_point(target_point_index + 1)
        if local_end_point.distance_squared_to(next_target) <= dist_sqr:
            target_point_index += 1
            continue

        var next_travel_dir: Vector3 = local_end_point.direction_to(next_target)
        if original_travel_dir.dot(current_travel_dir) <= original_travel_dir.dot(next_travel_dir):
            target_point_index += 1
            continue

        break

    target.position = local_target_point

    if debug_enable and debug_ik_target:
        _draw_ik_target()

func _update_recovery_target() -> void:
    # Select position between rest and attachment point, translate it below
    # the rest plane, and move end point towards it by a fixed distance
    var recovery_point: Vector3 = rest_position

func _update_target_rest() -> void:
    if not body.has_desired_movement:
        # TODO: parameters?
        const MAX_DISPLACEMENT_SQR: float = pow(0.1, 2.0)
        const TRAVEL_RATE: float = 0.2
        var rest_displacement_sqr: float = target_rest_position.distance_squared_to(local_end_point)
        if rest_displacement_sqr > MAX_DISPLACEMENT_SQR:
            target_rest_position = target_rest_position.move_toward(local_end_point, sqrt(rest_displacement_sqr) * TRAVEL_RATE * body.delta_time)
            target.position = target_rest_position
        return

    # Move rest target to oppose forward / rotation, such that this leg has a
    # minimal impact on body movement.
    var body_global_center: Transform3D = body.phys_state.transform.translated(body.phys_state.center_of_mass)
    var rest_rel_to_body: Vector3 = (
              body_global_center.affine_inverse()
            * global_transform.translated_local(target_rest_position).origin
    )

    if body.has_desired_rotation and (not body.phys_state.angular_velocity.is_zero_approx()):
        body_global_center.basis = body_global_center.basis.rotated(
                -body.phys_state.angular_velocity.normalized(),
                body.phys_state.angular_velocity.length() * body.delta_time
        )

    if body.has_desired_forward:
        var forward_velocity: Vector3 = body.desired_direction * body.desired_direction.dot(body.phys_state.linear_velocity)
        body_global_center.origin -= forward_velocity * body.delta_time

    target_rest_position = to_local(body_global_center * rest_rel_to_body)
    target.position = target_rest_position

## When targeting the final point, we may "reach" it without finding ground.
## This method returns true if the target should remain active, hoping to locate
## ground in a short time. This returns false if we find ground, stay very close
## to the target (TODO: for a short time), or pass it and miss.
func _should_wait_for_ground() -> bool:
    # NOTE: when waiting for ground, we should not consider the motion complete
    # until we have ground, pass the point, or get very close. Maybe consider a
    # timer to hold at the location for a short period, too.
    if not target_wait_for_ground:
        return false

    # Not at the final step goal, no need to wait here
    if target_point_index + 1 < target_point_list.size():
        return false

    # 1. touching ground is the end of the step
    if is_grounded:
        return false

    # 2. being very near the goal (TODO: for a short time)
    const GROUND_GOAL_DIST_SQR: float = 2.5e-5 # NOTE: 0.5cm
    var local_target_point: Vector3 = _get_target_point(target_point_index)
    var dist_sqr: float = local_end_point.distance_squared_to(local_target_point)

    if dist_sqr <= GROUND_GOAL_DIST_SQR:
        breakpoint # TODO: remove later
        return false

    # 3. passing the goal by some distance (maybe not count this?)
    const GOAL_MISS_DIST_SQR: float = 2.25e-4 # NOTE: 1.5cm
    var current_travel_dir: Vector3 = local_end_point.direction_to(local_target_point)
    var prev_target: Vector3 = _get_target_point(target_point_index - 1)
    var original_travel_dir: Vector3 = prev_target.direction_to(local_target_point)

    if current_travel_dir.dot(original_travel_dir) < 0.0 and dist_sqr > GOAL_MISS_DIST_SQR:
        #breakpoint # TODO: remove later
        return false

    # 1. not grounded
    # 2. further than ground goal distance
    # 3. traveling towards the goal, or not further than miss distance
    # Do not progress target, wait.
    # TODO: probably need a short timer here...
    return true

## Returns the local position of the target point at the given index. You must
## guarantee that the point exists as this does not perform bounds checks.
func _get_target_point(target_index: int) -> Vector3:
    var tp: Vector4 = target_point_list[target_index]
    var point: Vector3 = Vector3(tp.x, tp.y, tp.z)
    if tp.w < 0.0:
        point = to_local(point)
    return point

## Cleans up target state and sets target_rest_position to final_point
func _on_target_finished(final_point: Vector3) -> void:
    target_rest_position = final_point
    target.position = target_rest_position

    target_point_index = -1
    target_point_index_ik_checked = -1

    target_allow_skipping_ahead = false
    target_wait_for_ground = false

    if debug_enable:
        if debug_move_reason:
            _draw_move_reason(true)
        if is_stepping:
            _draw_step_target(true)
        if debug_ik_target:
            _draw_ik_target()

    if is_recovering:
        is_recovering = false

    if is_stepping:
        time_since_last_step = 0.0
        is_stepping = false

## Returns the legs cross-paired with this one.
func get_cross_paired_legs() -> Array[CrawlerLeg]:
    if cross_paired.size() > 0:
        return cross_paired

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
    if is_left:
        idx = index + 1
    else:
        idx = index - 1

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
        chain: PhysicalBoneChain3D,
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
    elif beam_res.relative_attach == -1:
        beam_joint.node_a = parent_body.get_path()
    else:
        var relative_part: PhysicalBonePart3D = chain.get_child(part.get_index() + beam_res.relative_attach) as PhysicalBonePart3D
        if relative_part:
            beam_joint.node_a = relative_part.get_path()

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
    ground_cast.settings = setting.ground_spring_setting

    step_cast.collision_mask = setting.step_cast_collision_mask
    step_cast.shape = setting.step_cast_shape
    step_cast.target_position = Vector3.UP * (setting.step_cast_end - setting.step_cast_start)

func _draw_step_cast() -> void:
    var shape_origin: Vector3 = step_cast.target_position
    var shape_color: Color
    if step_cast.is_colliding():
        shape_origin *= step_cast.get_closest_collision_unsafe_fraction()
        shape_color = Color.OLIVE_DRAB
    else:
        shape_color = Color.DARK_SLATE_GRAY

    _debug_step_cast_vector = DebugDraw.vector(
            step_cast.global_position,
            step_cast.global_basis * shape_origin,
            shape_color,
            _debug_step_cast_vector
    )
    _debug_step_cast_shape = DebugDraw.sphere(
            step_cast.global_transform * shape_origin,
            (step_cast.shape as SphereShape3D).radius,
            shape_color,
            _debug_step_cast_shape
    )

func _draw_step_target(clear: bool = false) -> void:
    if clear or (not next_step_target_global.is_finite()):
        _debug_target_sphere = DebugDraw.sphere(
                Vector3.ZERO,
                0.0,
                Color.TRANSPARENT,
                _debug_target_sphere,
                0.0
        )
        return
    _debug_target_sphere = DebugDraw.sphere(
            next_step_target_global,
            (step_cast.shape as SphereShape3D).radius,
            Color.FIREBRICK * Color(1.0, 1.0, 1.0, 0.3),
            _debug_target_sphere,
            1.0
    )

func _draw_move_reason(clear: bool = false) -> void:
    if clear:
        _debug_move_reason_text_id = DebugDraw.text(
                Vector3.INF,
                '',
                Color.DARK_ORANGE,
                16.0,
                _debug_move_reason_text_id,
                0.1
        )
        return
    _debug_move_reason_text_id = DebugDraw.text(
            target.global_position,
            _debug_move_reason_text,
            Color.DARK_ORANGE,
            24.0,
            _debug_move_reason_text_id,
            1.0
    )

func _draw_ik_target() -> void:
    _debug_ik_sphere = DebugDraw.sphere(
            target.global_position,
            0.02,
            Color.AQUA,
            _debug_ik_sphere
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
            ground_position,
            ground_normal * 0.5,
            Color.CORNFLOWER_BLUE,
            _debug_ground_normal_vector
    )

func _draw_rest_area() -> void:
    var color: Color = Color.GREEN
    if not is_comfortable:
        color = Color.RED
    _debug_rest_circle = DebugDraw.circle(
            to_global(step_transform * rest_position),
            comfort_distance,
            global_basis.y,
            16,
            color,
            _debug_rest_circle,
            1.0
    )
