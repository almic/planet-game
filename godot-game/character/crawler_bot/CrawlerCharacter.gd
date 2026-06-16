@tool
class_name CrawlerCharacter extends CharacterController


@warning_ignore("unused_private_class_variable")
@export_tool_button('Build Crawler', 'SphereMesh')
var _btn_build_crawler = editor_build_crawler

## Whole body mass of the crawler. This is used with 'Leg Mass Ratio' to
## disperse the mass between the main body and the individual leg segments.
@export_range(0.01, 100.0, 0.01, 'or_greater')
var total_mass: float = 30.0:
    set(value):
        total_mass = value
        _update_body_mass()

@export_custom(PROPERTY_HINT_NONE, '', PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var _single_leg_mass: float = 0.0

@export_range(0.01, 8.0, 0.01, 'or_greater')
var max_speed: float = 3.0

@export_range(0.0, 30.0, 0.1, 'or_greater', 'radians_as_degrees')
var max_pitch: float = deg_to_rad(12.0)

@export_range(0.0, 360.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rotation_acceleration: float = deg_to_rad(270.0)

## Maximum rotation speed when turning
@export_range(0.1, 180.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rotation_rate: float = deg_to_rad(180.0)

@export_range(0.1, 1.0, 0.01, 'or_greater')
var rotation_overshoot: float = 0.2

@export var skeleton: Skeleton3D

@export var leg_ik: IterateIK3D


@export_group('Physical Skeleton')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var enable_physical_skeleton: bool = true

@export var physical_skeleton: PhysicalSkeleton

#region IK Parameters
@export_group('IK Parameters', 'ik')

## Number of iteration loops used by the IK solver to produce more accurate results.
@export_range(0, 10, 1, 'or_greater')
var ik_max_iterations: int = 4:
    set(value):
        ik_max_iterations = value
        _queue_update_ik_settings()

## The target solve distance between the end bone and the target node.
## Iteration will only run while the distance is greater than this value.
@export_range(0.0, 1.0, 0.001, 'or_greater')
var ik_min_distance: float = 0.001:
    set(value):
        ik_min_distance = value
        _queue_update_ik_settings()

## The total angular change allowed per second. This is divided evenly between
## each iteration relative to the current `Engine.physics_ticks_per_second`,
## unlike the Godot implementation which applies it per-iteration and doesn't
## consider frame rate or physics TPS.
@export_range(0.01, 180.0, 0.01, 'radians_as_degrees', 'suffix:°/s')
var ik_angular_delta_limit: float = deg_to_rad(30.0):
    set(value):
        ik_angular_delta_limit = value
        _queue_update_ik_settings()

## Generally, enabling this will copy the current skeleton pose and process that.
## When disabled, it is loaded once on the first run and never again.
@export var ik_deterministic: bool = true:
    set(value):
        ik_deterministic = value
        _queue_update_ik_settings()

## Generally, this break limitations by treating the incoming rotation as the
## rest rotation. It should be turned off if the skeleton is modified by
## animations or other modifiers.
@export var ik_mutable_bone_axes: bool = false:
    set(value):
        ik_mutable_bone_axes = value
        _queue_update_ik_settings()
#endregion IK Parameters

#region Leg Parameters
@export_group('Leg Parameters', 'body')

## How many legs are equivalent to the mass of the central body. When greater
## than the total number of legs, more than 50% of the total mass will be
## concentrated in the main body.
@export_range(1.0, 16.0, 0.01, 'or_greater')
var body_leg_mass_ratio: float = 5.0:
    set(value):
        body_leg_mass_ratio = value
        _update_body_mass()

## How far off the ground to keep the body's center of mass
@export_range(0.0, 0.5, 0.01, 'or_greater', 'suffix:m')
var body_height_offset: float = 0.5

## How for the body "settles" when affected by gravity, reduces as the body
## becomes parallel to gravity.
@export_range(0.0, 0.2, 0.01, 'or_greater', 'suffix:m')
var body_gravity_offset: float = 0.1

## Stiffness of the spring used to offset the body from the ground
@export_range(0.01, 2.0, 0.01, 'or_greater')
var body_height_spring_stiffness: float = 1.6

## Damping of the spring used to offset the body from the ground
@export_range(0.01, 1.0, 0.01, 'or_greater')
var body_height_spring_damping: float = 0.8

## Percentage of total legs necessary to lift the body.
@export_range(0.0, 1.0, 0.01)
var body_leg_lift_ratio: float = 0.5

## How much effective acceleration legs can apply to the body. Should be just
## enough to be stable while being pushed and entering extreme inclines.
@export_range(0.01, 30.0, 0.01, 'or_greater')
var body_max_leg_force: float = 20.0

## The number of grounded legs necessary for jumping
@export_range(1, 8, 1, 'or_less')
var body_legs_needed_for_jump: int = 3
#endregion Leg Parameters

#region Debug
@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false

@export var debug_new_leg_mode: bool = false:
    set(value):
        debug_new_leg_mode = value
        _update_leg_modes()

@export var debug_leg_polygon: bool = false
var _debug_leg_polyline: int = 0

@export var debug_leg_gravity: bool = false
var _debug_leg_gravity_vec: int = 0
#endregion Debug

var legs: Array[CrawlerLeg]
"""
var leg_distance_constraint_list: Array[DistanceJoint3D]
"""

var target_position: Vector3 = Vector3.INF
var target_direction: Vector3 = Vector3.INF

var is_stepping: bool:
    get():
        return has_desired_forward or has_desired_rotation

var has_desired_rotation: bool = false
var grounded_leg_count: int = 0
var grounded_leg_avg_displacement: float
var leg_update_data: PackedVector3Array
var leg_polygon: PackedVector2Array
var leg_gravity_power: PackedFloat64Array

var linear_leg_accel: Vector3
var angular_leg_accel: Vector3

var _is_update_ik_queued: bool = false
var _next_chain_ik_setting_index: int = 0


func editor_build_crawler() -> void:
    var dialog: Window
    if self != get_tree().edited_scene_root:
        dialog = AcceptDialog.new()
        dialog.dialog_text = (
            'You may only build crawlers within their scene file.\nTo build '
            + 'this crawler, open the scene:\n\n%s'
        ) % scene_file_path
    else:
        dialog = ConfirmationDialog.new()
        dialog.dialog_text = 'This will create nodes and add them to this scene file, are you sure?'
        dialog.confirmed.connect(build_crawler)

    EditorInterface.popup_dialog_centered(dialog)

func build_crawler() -> void:
    if not physical_skeleton:
        push_error('Missing a physical skeleton. This is needed to build the bone bodies.')
        return

    _load_legs()

    for leg in legs:
        if not leg.physical_bone_chain:
            continue

        # Teleport leg to correct location
        physical_skeleton.build_chain(leg.physical_bone_chain, leg.build_custom_joint)

func _ready() -> void:
    super._ready()

    if enable_physical_skeleton:
        physical_skeleton.skeleton = skeleton

    _load_legs(true)
    _update_body_mass()
    _queue_update_ik_settings()

    if Engine.is_editor_hint():
        return

    var count: int = legs.size()
    leg_update_data.resize(count * 3)
    leg_gravity_power.resize(count)
    leg_gravity_power.fill(0.0)

    # Collect leg rigid bodies to ignore for shape casts
    var child_bodies: Array[RID]
    for body in find_children('', 'CollisionObject3D'):
        if body is CollisionObject3D:
            child_bodies.append(body.get_rid())

    # Get the chain end bones for each leg target
    var target_bones: Dictionary = {}
    for setting in range(leg_ik.setting_count):
        target_bones.set(leg_ik.get_target_node(setting), leg_ik.get_end_bone(setting))

    # Collect target nodes for ground bones
    var ground_targets: Dictionary[int, Node3D] = {}
    var attachments: Array[ModifierBoneTarget3D]
    attachments.assign(skeleton.find_children('', 'ModifierBoneTarget3D'))
    for attach in attachments:
        var target: Node3D
        if enable_physical_skeleton:
            var bodies: Array[RigidBody3D]
            bodies.assign(attach.find_children('', 'RigidBody3D', false))
            if bodies.size() == 0:
                continue
            target = bodies[0]
        else:
            target = attach

        ground_targets.set(
            attach.bone,
            target
        )

    # Initialize legs
    for leg in legs:
        leg.setup(
                ground_targets,
                target_bones.get(leg_ik.get_path_to(leg.target)),
                child_bodies
        )

    _update_leg_modes()

    # Should be off for the editor, on in-game
    leg_ik.active = true

    if enable_physical_skeleton:
        physical_skeleton.active = true
        physical_skeleton.modification_processed.connect(_update_legs)
        # NOTE: deterministic has the effect of just copying the joint positions
        #       into the working chain state, so as long as the skeleton is
        #       being updated by physics, "deterministic" is what we want from IK
        leg_ik.deterministic = true
        leg_ik.modification_processed.connect(physical_skeleton.on_pose_finalized)
    else:
        # Must run this method, for some reason Skeleton3D respects custom
        # modifiers "active" flag on load, while IterateIK3D definitely still
        # processes once even though it is also disabled
        physical_skeleton.setup_body()
        leg_ik.modification_processed.connect(_on_leg_pose_updated)
        # NOTE: ensure this is off when in pure IK mode, see above note for
        #       physics to understand why this might be enabled
        leg_ik.deterministic = false

    desired_surface_friction = 0.0

func get_nice_path(to: Node = null) -> NodePath:
    if not to:
        to = self
    var root_node: Node = get_tree().edited_scene_root
    if not root_node:
        root_node = get_tree().current_scene
    if not root_node:
        root_node = get_viewport()
    if not root_node:
        root_node = get_window()
    if root_node:
        return root_node.get_path_to(to)
    return to.get_path()

func _load_legs(is_initialization: bool = false) -> void:
    for old_leg in legs:
        old_leg.index = -1
        old_leg.body = null

    # Load legs from children
    legs.assign(find_children('', 'CrawlerLeg'))

    var count: int = legs.size()
    """
    leg_distance_constraint_list.resize(count)
    """
    for i in range(count):
        var leg: CrawlerLeg = legs[i]
        leg.body = self
        leg.index = i

        if not is_initialization:
            continue

        if enable_physical_skeleton:
            if leg.physical_bone_chain:
                physical_skeleton.prepare_custom_joints(leg.physical_bone_chain, leg.prepare_custom_joint)
            else:
                continue
                push_error(
                    (
                        'CrawlerCharacter at %s has a CrawlerLeg at %s which is '
                        + 'missing a physical bone chain resource. Please give it '
                        + 'a resource or delete the leg node.'
                    ) % [get_nice_path(), get_nice_path(leg)]
                )

        if Engine.is_editor_hint():
            continue

        """
        # Create distance constraint for the leg
        var dc := DistanceJoint3D.new()
        dc.set_param(DistanceJoint3D.PARAM_LIMITS_SPRING_STIFFNESS, 44.847)
        dc.set_param(DistanceJoint3D.PARAM_LIMITS_SPRING_DAMPING, 17.844)
        dc.set_param(DistanceJoint3D.PARAM_DISTANCE_MAX, 0.0)
        leg_distance_constraint_list[i] = dc
        add_child(dc)
        """

func _queue_update_ik_settings() -> void:
    if _is_update_ik_queued:
        return
    _is_update_ik_queued = true
    _update_ik_settings.call_deferred()

func _update_ik_settings() -> void:
    _is_update_ik_queued = false
    if not leg_ik:
        return

    leg_ik.max_iterations = ik_max_iterations
    leg_ik.min_distance = ik_min_distance
    leg_ik.angular_delta_limit = ik_angular_delta_limit / (InputManager.PHYSICS_TICKS * ik_max_iterations)
    leg_ik.deterministic = ik_deterministic
    leg_ik.mutable_bone_axes = ik_mutable_bone_axes

func _on_leg_pose_updated() -> void:
    for leg in legs:
        leg.pose_updated()

func damage(source: Object, amount: float, hit_point: Vector3) -> void:
    print('Took %f damage from %s at position %s' % [amount, source.name, str(hit_point)])

func _update_body_mass() -> void:
    """
    My math homework for these equations:

    TotalMass = B + nL
    B = Ratio * L
    L = B / Ratio

    TotalMass = B + n(B / Ratio)
    TotalMass = B * (1 + (n / Ratio))
    B = TotalMass / (1 + (n / Ratio))

    TotalMass = (Ratio * L) + nL
    TotalMass = L * (Ratio + n)
    L = TotalMass / (Ratio + n)
    """
    var leg_count: int = legs.size()
    if leg_count == 0:
        return # Not ready yet
    var body_mass: float = total_mass / (1 + (leg_count / body_leg_mass_ratio))
    var leg_mass: float = total_mass / (leg_count + body_leg_mass_ratio)

    mass = body_mass
    _single_leg_mass = leg_mass

    # Now for the hard part, distribute leg_mass to bone bodies in physical chains
    var bone_part_map: Dictionary[int, PhysicalBonePart3D] = physical_skeleton.get_bone_part_map()
    for chain in physical_skeleton.chain_list:
        var bone_total_length: float = 0.0
        var end_bone: int = skeleton.find_bone(chain.resource.end_bone)
        for index in range(chain.part_count):
            var bone_idx: int
            if index + 1 < chain.part_count:
                bone_idx = chain.bone_list[index + 1]
            else:
                bone_idx = end_bone
            bone_total_length += skeleton.get_bone_rest(bone_idx).origin.length()
        for index in range(chain.part_count):
            var bone_for_body: int = chain.bone_list[index]
            var body: PhysicalBonePart3D = bone_part_map.get(bone_for_body)
            if not body:
                push_error("Bone %s does not have an associated RigidBody3D! Fix!!" % skeleton.get_bone_name(bone_for_body))
                return
            var bone_for_length: int
            if index + 1 < chain.part_count:
                bone_for_length = chain.bone_list[index + 1]
            else:
                bone_for_length = end_bone
            var length: float = skeleton.get_bone_rest(bone_for_length).origin.length()
            body.mass = leg_mass * (length / bone_total_length)

func _update_leg_modes() -> void:
    for leg in legs:
        leg.use_new_leg_mode = debug_new_leg_mode

func _handle_input() -> void:

    if target_position.is_finite() and (target_position - position).length_squared() > 4.0:
        target_direction = (target_position - position).normalized()
        desired_direction = (target_position - position).normalized()
        desired_speed = max_speed
    elif not desired_direction.is_zero_approx():
        desired_direction = Vector3.ZERO
        desired_speed = 0.0
        target_position = Vector3.INF

func _update_ground(state: PhysicsDirectBodyState3D) -> void:

    is_on_floor = false
    is_slipping = false
    ground_normal = Vector3.ZERO
    ground_position = Vector3.ZERO
    ground_velocity = Vector3.ZERO

    for leg in legs:
        leg.pre_update(state)

    # NOTE: different order of operations when in virtual mode
    if not enable_physical_skeleton:
        _update_legs()

    # This kicks off several callbacks:
    # PHYSICS:
    #     1. Matches skeleton pose to physical joints
    #     2. Calls '_update_legs()' which provides the current pose and calculates new targets
    #     3. IterateIK moves joints towards targets
    #     4. PhysicalSkeleton calculates joint motor velocities for the next physics step
    # VIRTUAL:
    #     1. IterateIK moves joints towards targets
    #     2. Calls '_on_leg_pose_updated()' which copies the IK results to leg targets
    skeleton.advance(state.step, true)

    if grounded_leg_count > 0:
        is_on_floor = true
        var inv_legs: float = 1.0 / float(grounded_leg_count)
        ground_normal *= inv_legs
        ground_position *= inv_legs
        ground_velocity *= inv_legs

        if ground_normal.is_zero_approx():
            ground_normal = state.transform.basis.y
        else:
            ground_normal = ground_normal.normalized()

        if grounded_leg_count >= body_legs_needed_for_jump:
            has_landed_on_ground_for_jump = true
    else:
        ground_position = Vector3.INF

func _update_legs() -> void:
    # NOTE: this is called before IK, so virtual cannot copy the pose yet
    if enable_physical_skeleton:
        for chain in physical_skeleton.chain_list:
            # NOTE: for now, the only chains are IK enabled, so just initialize everything
            if not chain.is_ik_initialized:
                if leg_ik.setting_count < _next_chain_ik_setting_index + 1:
                    leg_ik.set_setting_count(_next_chain_ik_setting_index + 1)
                chain.init_ik(leg_ik, _next_chain_ik_setting_index)
                _next_chain_ik_setting_index += 1

            # Disable IK behavior on the chain and update legs
            if chain.is_any_motor_broken:
                # NOTE: setting node path to empty effectively disables that ik setting
                leg_ik.set_target_node(chain.ik_setting_id, NodePath(""))
                # TODO: tell CrawlerLegs about this so they can change behavior

        _on_leg_pose_updated()

    for leg in legs:
        leg.check_early_step()

    grounded_leg_count = 0

    for leg in legs:
        leg.update()

        # At this point, all legs have computed final ground states
        if leg.apply_ground_forces:
            grounded_leg_count += 1
            ground_normal += leg.ground_normal
            ground_position += leg.ground_point
            ground_velocity += leg.ground_velocity

        """
        # Update distance constraint
        if not enable_physical_skeleton:
            continue

        var dc: DistanceJoint3D = leg_distance_constraint_list[leg.index]
        dc.global_position = leg.target.global_position
        if dc.node_b:
            dc.force_update_joint()
        else:
            var bone: int = skeleton.get_bone_parent(leg.target_bone_idx)
            for joint_data in physical_skeleton.joints:
                if joint_data.bone_idx != bone:
                    continue
                # NOTE: this will update the joint
                dc.node_b = joint_data.body.get_path()
                var node_b_pos: Vector3 = skeleton.get_bone_rest(leg.target_bone_idx).origin
                dc.set_point_param(DistanceJoint3D.POINT_PARAM_B, node_b_pos)
                break
        """


func _calculate_ground_vectors(state: PhysicsDirectBodyState3D) -> void:

    ground_direction = Vector3.ZERO
    ground_rel_con_velocity = Vector3.ZERO
    ground_friction = Vector3.ZERO
    angular_leg_accel = Vector3.ZERO
    linear_leg_accel = Vector3.ZERO

    # NOTE: is_on_floor is effectively a `grounded_leg_count != 0` test
    if not is_on_floor:
        return

    ground_rel_con_velocity = state.linear_velocity - ground_velocity
    ground_velocity = ground_rel_con_velocity.slide(state.transform.basis.y).slide(ground_normal)

    # TODO: stopping friction when not traveling
    """
    # Gather relative velocity from all legs, using last gravity power
    var max_leg_mass: float
    if is_zero_approx(body_leg_lift_ratio):
        max_leg_mass = total_mass
    else:
        max_leg_mass = total_mass / (legs.size() * body_leg_lift_ratio)

    var body_friction: float = PhysicsServer3D.body_get_param(get_rid(), PhysicsServer3D.BODY_PARAM_FRICTION)

    for leg in legs:
        if not leg.is_grounded:
            continue

        var leg_ground_velocity: Vector3 = leg.ground_rel_con_velocity.slide(leg.ground_normal)

        # "Effective mass" per leg
        var leg_mass: float = minf(total_mass * leg_gravity_power[leg.index], max_leg_mass)

        # Reduce applied force when leg should not be "holding" the ground
        if not leg.apply_ground_forces:
            leg_mass *= 0.1

        # Collision force applying into the ground, only allow impacts and not pulls
        var leg_force: Vector3 = leg_mass * leg.ground_normal * minf(leg.ground_normal.dot(leg.ground_rel_con_velocity), 0.0)

        # NOTE: Save linear friction for ground_friction
        linear_leg_accel -= state.inverse_inertia * leg_force

        # Friction
        var friction: Vector3 = leg_ground_velocity * leg_mass * absf(minf(body_friction, leg.ground_friction))
        ground_friction -= state.inverse_inertia * friction

        # Angular acceleration from collision and friction
        leg_force += friction
        angular_leg_accel -= state.inverse_inertia_tensor * (leg.ground_point - state.transform.origin - state.center_of_mass).cross(leg_force)

        # Push into the ground here
        var ground_state := PhysicsServer3D.body_get_direct_state(leg.ground_body)
        if ground_state:
            ground_state.apply_force(leg_force, leg.ground_point - ground_state.transform.origin)
    """

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO

    # Legs need final ground velocities for some updates
    for leg in legs:
        leg.post_update()


func _custom_pre_movement_forces(state: PhysicsDirectBodyState3D) -> void:
    _solve_leg_forces(state)

    _solve_rotation(state)

func _solve_leg_forces(state: PhysicsDirectBodyState3D) -> void:
    if grounded_leg_count < 1:
        return

    # Add leg accelerations immediately, the next section is responsible for stabilizing the crawler
    state.linear_velocity += linear_leg_accel * state.step
    state.angular_velocity += angular_leg_accel * state.step

    var rid: RID = get_rid()

    var total_gravity: Vector3 = state.total_gravity * desired_gravity
    var gravity_direction: Vector3 = Vector3.ZERO
    if not state.total_gravity.is_zero_approx():
        gravity_direction = state.total_gravity.normalized()

    var leg_mass: float = total_mass / legs.size()
    var max_leg_mass: float

    if is_zero_approx(body_leg_lift_ratio):
        max_leg_mass = total_mass
    else:
        max_leg_mass = total_mass / (legs.size() * body_leg_lift_ratio)

    var shared_mass: float = minf(total_mass / grounded_leg_count, max_leg_mass)

    var max_force: float = body_max_leg_force * leg_mass

    var iteration: int = 0
    # NOTE: 2 is probably enough, but I chose 3 so that it definitely would be accurate
    var max_iterations: int = 3
    var sub_step: float = state.step / max_iterations
    var old_transform: Transform3D = state.transform

    var total_grav_vec: Vector3 = Vector3.ZERO

    while iteration < max_iterations:
        iteration += 1

        grounded_leg_avg_displacement = 0.0

        var spring_direction: Vector3 = state.transform.basis.y

        var gravity_alignment: float = state.transform.basis.tdoty(gravity_direction) * desired_gravity
        var total_height_offset: float = body_height_offset + body_gravity_offset * gravity_alignment

        var poly_front_index: int = 0
        if debug_enable and debug_leg_polygon:
            leg_polygon.clear()

        var body_plane: Plane = Plane(state.transform.basis.y, state.transform.origin + state.center_of_mass)

        for leg in legs:
            if not leg.apply_ground_forces:
                continue

            var global_attachment: Vector3 = state.transform * leg.attachment_point

            # These lines copied from CrawlerLeg
            var attachment_plane: Plane = Plane(-state.transform.basis.y, global_attachment)
            leg.ground_offset = attachment_plane.distance_to(leg.ground_point) - total_height_offset

            grounded_leg_avg_displacement += absf(leg.ground_offset)

            var spring_midpoint: Vector3 = (0.5 * (leg.ground_point + global_attachment)) - state.transform.origin
            leg_update_data[leg.index * 3] = spring_midpoint
            leg_update_data[leg.index * 3 + 1] = state.get_velocity_at_local_position(spring_midpoint)
            leg_update_data[leg.index * 3 + 2] = body_plane.project(spring_midpoint + state.transform.origin) - state.transform.origin

            if debug_enable and debug_leg_polygon:
                var plane_point: Vector3 = body_plane.project(leg.ground_point) - (state.transform.origin + state.center_of_mass)
                var polygon_point: Vector2 = Vector2(state.transform.basis.tdotx(plane_point), state.transform.basis.tdotz(plane_point))
                leg_polygon.insert(poly_front_index, polygon_point)
                if leg.is_left:
                    poly_front_index += 1

        grounded_leg_avg_displacement /= grounded_leg_count

        _calculate_leg_gravity_power(state)

        for leg in legs:
            if not leg.apply_ground_forces:
                continue

            var offset: float = leg.ground_offset
            offset = signf(offset) * minf(absf(offset), grounded_leg_avg_displacement)

            var spring_midpoint: Vector3 = leg_update_data[leg.index * 3]
            var local_velocity: Vector3 = leg_update_data[leg.index * 3 + 1]
            var anti_gravity_point: Vector3 = leg_update_data[leg.index * 3 + 2]
            var rel_ground_velocity: Vector3 = local_velocity - leg.ground_velocity

            var speed: float = spring_direction.dot(rel_ground_velocity)

            var spring_force: float = 100.0 * body_height_spring_stiffness * -offset * shared_mass
            var damp_force: float = 10.0 * body_height_spring_damping * -speed * shared_mass
            var total_force: float = clampf(spring_force + damp_force, -max_force, max_force)

            var force_vec: Vector3 = total_force * spring_direction
            state.apply_impulse(
                force_vec * sub_step,
                spring_midpoint
            )

            # Negate gravity, not exceeding the capability of a single leg
            var grav_force_vec: Vector3
            if true:
                grav_force_vec = -total_gravity * minf(total_mass * leg_gravity_power[leg.index], max_leg_mass)
                if debug_enable and debug_leg_gravity:
                    total_grav_vec += (
                          (grav_force_vec + (anti_gravity_point - state.center_of_mass)) * sub_step
                    )
            else:
                grav_force_vec = -total_gravity * shared_mass

            state.apply_impulse(
                grav_force_vec * sub_step,
                anti_gravity_point
            )

            var ground_state := PhysicsServer3D.body_get_direct_state(leg.ground_body)
            if ground_state:
                ground_state.apply_impulse(
                    -(force_vec + grav_force_vec) * sub_step,
                    leg.ground_point - ground_state.transform.origin
                )

        if iteration >= max_iterations:
            break

        # Update the body virtually
        state.transform.origin += state.linear_velocity * sub_step
        var angular_len: float = state.angular_velocity.length()
        if not is_zero_approx(angular_len):
            state.transform.basis = state.transform.basis.rotated(state.angular_velocity / angular_len, angular_len * sub_step)
            # NOTE: when changing rotation, need to tell physics server to update so inertia is accurate
            PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, state.transform)

    if debug_enable:
        if debug_leg_polygon:
            var polygon: PackedVector3Array
            polygon.resize(grounded_leg_count)
            for i in range(grounded_leg_count):
                polygon[i] = state.transform * Vector3(leg_polygon[i].x, grounded_leg_avg_displacement, leg_polygon[i].y)
            _debug_leg_polyline = DebugDraw.polyline(
                polygon,
                true,
                Color.MEDIUM_PURPLE,
                _debug_leg_polyline,
                0.05
            )
        if debug_leg_gravity:
            _debug_leg_gravity_vec = DebugDraw.vector(
                state.transform.origin,
                total_grav_vec * 0.1,
                Color.MEDIUM_SEA_GREEN,
                _debug_leg_gravity_vec,
                0.1
            )

    # NOTE: There used to be code here that moved the angular velocity back towards
    #       the incoming value, but this was causing bobbing because the whole
    #       purpose of the method is to stabilize angular rotation, so undoing
    #       that work meant it would perpetuate small velocities forever.

    # Reset changes to the transform
    state.transform = old_transform
    PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, state.transform)


func _calculate_leg_gravity_power(state: PhysicsDirectBodyState3D) -> void:
    # NOTE: Parameterize the iteration count
    const MAX_ITERATIONS: int = 2
    # NOTE: parameterize the rate of rest (decay???)
    var decay_rate: float = pow(0.5, state.step)
    var dead_decay_rate: float = pow(0.1, state.step / 0.1) # roughly 10% after 0.1 seconds

    var count: int = leg_gravity_power.size()
    var points: PackedVector3Array
    points.resize(count)
    for leg in legs:
        if not leg.apply_ground_forces:
            points[leg.index] = Vector3.INF
            continue

        points[leg.index] = leg_update_data[leg.index * 3 + 2] - state.center_of_mass

    if grounded_leg_count < 2:
        for i in range(count):
            if points[i].is_finite():
                leg_gravity_power[i] = 1.0
            else:
                leg_gravity_power[i] = 0.0
        return

    var rots: PackedVector3Array
    rots.resize(count)
    rots.fill(Vector3.ZERO)
    var rot_normals: PackedVector3Array
    rot_normals.resize(count)
    rot_normals.fill(Vector3.ZERO)

    # NOTE: Used to calculate power share by assuming a leg is capable of lifting the entire body,
    #       although in practice this will have limitations.
    var anti_gravity: Vector3 = -state.total_gravity * state.step * total_mass

    var markiplier: float = minf(2.0 / float(grounded_leg_count), 1.0)
    var power_avg: float = 1.0 / float(grounded_leg_count)
    var it_step: float = 1.0 / float(MAX_ITERATIONS)
    for iteration in range(MAX_ITERATIONS):
        var new_power := PackedFloat64Array(leg_gravity_power)

        var rot_total: Vector3 = Vector3.ZERO
        for i in range(count):
            var point: Vector3 = points[i]
            if not point.is_finite():
                continue

            rot_normals[i] = state.inverse_inertia * point.cross(anti_gravity)
            rots[i] = rot_normals[i] * maxf(new_power[i], 0.001)

            rot_total += rots[i]

        # Scale method, each point moves its work to match what is needed, and is always slowly relaxing
        var power_total: float = 0.0
        for i in range(count):
            var work: float = new_power[i]
            var max_length: float = rot_normals[i].length()

            var new_work: float = work
            if not legs[i].apply_ground_forces:
                new_work *= dead_decay_rate
            elif not is_zero_approx(max_length):
                var grad: Vector3 = rots[i]
                var new_grad: Vector3 = grad - (rot_total * markiplier)
                var grad_dir: Vector3 = rot_normals[i] / max_length
                var dot_grad: float = new_grad.dot(grad_dir)

                if dot_grad < 0.0:
                    new_grad = Vector3.ZERO
                else:
                    new_grad = grad_dir * dot_grad

                new_work = new_grad.length() / max_length
                new_work *= pow(decay_rate, new_work / power_avg)

            new_power[i] = maxf(new_work, 0.0)
            power_total += new_power[i]

        if power_total > 0.0:
            for i in range(count):
                new_power[i] /= power_total

        power_total = 0.0
        for i in range(count):
            # NOTE: parameterize the rate of change
            leg_gravity_power[i] = move_toward(leg_gravity_power[i], new_power[i], 4.0 * state.step * it_step)
            power_total += leg_gravity_power[i]

        if power_total > 1.0:
            for i in range(count):
                leg_gravity_power[i] /= power_total

func _solve_rotation(state: PhysicsDirectBodyState3D) -> void:

    var can_do_yaw: bool = target_direction.is_finite()
    if can_do_yaw:
        for leg in legs:
            if (not leg.is_comfortable) and (not leg.is_stepping):
                can_do_yaw = false
                break

    has_desired_rotation = false

    # Must have at least 1 leg grounded to perform rotation
    if grounded_leg_count == 0:
        # TODO: damp rotation as if by air friction
        return

    var leg_count: int = legs.size()
    var grounded_leg_factor: float = float(grounded_leg_count) / float(leg_count)

    var preferred_forward: Vector3
    var preferred_right: Vector3

    var main_legs: Array[CrawlerLeg] = [
        legs[0], legs[1],
        legs[leg_count - 2], legs[leg_count - 1]
    ]
    var ground_points: PackedVector3Array
    ground_points.resize(4)

    var using_rest_point: bool = false
    var using_ground_points: bool = true
    for i in range(4):
        var leg: CrawlerLeg = main_legs[i]
        if leg.apply_ground_forces:
            ground_points[i] = leg.ground_point
        elif leg.is_stepping:
            ground_points[i] = leg.global_transform * leg.step_target
        elif using_rest_point:
            # Cannot use more than 1 rest point, use current orientation
            preferred_forward = -state.transform.basis.z
            preferred_right = state.transform.basis.x
            using_ground_points = false
            break
        else:
            using_rest_point = true
            ground_points[i] = leg.target_global_rest

    if using_ground_points:
        preferred_forward = (
                  (ground_points[0] - ground_points[2])
                + (ground_points[1] - ground_points[3])
        ).normalized()
        preferred_right = (
                  (ground_points[1] - ground_points[0])
                + (ground_points[3] - ground_points[2])
        ).normalized()

    var preferred_up: Vector3 = preferred_right.cross(preferred_forward).normalized()

    var current_forward: Vector3 = -state.transform.basis.z
    var current_right: Vector3 = state.transform.basis.x

    var yaw: float
    if can_do_yaw:
        # Only yaw when this is true:
        # r > pow(0.03125 - 0.03125 * cos_theta, 0.25)
        # NOTE: xz_dot == r
        var xz_dot: float = 1.0 - absf(preferred_up.dot(target_direction))
        var cos_theta: float = preferred_forward.dot(target_direction)
        if xz_dot > pow(0.03125 - 0.03125 * cos_theta, 0.25):
            yaw = current_forward.signed_angle_2(target_direction, preferred_up)

    var roll: float = current_right.signed_angle_2(preferred_right, -preferred_forward)
    var pitch: float = current_forward.signed_angle_2(preferred_forward, preferred_right)

    var angular: Vector3 = Vector3(pitch, yaw, roll)
    angular.x = 0.0
    angular.z = 0.0

    # roughly 0.5 degrees
    if angular.length_squared() > 7.62e-5:
        has_desired_rotation = true

    var max_angular: Vector3 = angular / state.step
    var limited_angular: Vector3 = angular.sign() * max_angular.abs().minf(rotation_rate * (1.0 / rotation_overshoot))
    var target_angular: Vector3 = state.transform.basis * limited_angular

    # TODO: this is bad, please figure it out. It rotates WAY too fast with acceleration, should
    #       just add angular velocity to attempt to reach target directions.
    #       I just changed it so it doesn't negate incoming velocity when it has zero desired change.
    state.angular_velocity += target_angular * (1.0 + rotation_overshoot) * state.step * grounded_leg_factor
    #state.angular_velocity += target_angular * (1.0 + rotation_overshoot) * state.step * rotation_acceleration * grounded_leg_factor

    if (not has_desired_rotation) and state.angular_velocity.length_squared() < 7.62e-5:
        # Low angular velocity, facing the target, clear target
        target_direction = Vector3.INF
