@tool
extends RigidBody3D


@export_tool_button('Build Physical Skeleton')
var _btn_build_skeleton = editor_build_physical_skeleton


## Whole body mass of the crawler. This is used with 'Leg Mass Ratio' to
## disperse the mass between the main body and the individual leg segments.
@export_range(0.01, 100.0, 0.01, 'or_greater')
var total_mass: float = 30.0:
    set(value):
        total_mass = value
        _update_body_mass()

@export_custom(PROPERTY_HINT_NONE, '', PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var _single_leg_mass: float = 0.0

## How many legs are equivalent to the mass of the central body. When greater
## than the total number of legs, more than 50% of the total mass will be
## concentrated in the main body.
@export_range(1.0, 16.0, 0.01, 'or_greater')
var body_leg_mass_ratio: float = 5.0:
    set(value):
        body_leg_mass_ratio = value
        _update_body_mass()


@export var chain_setting_list: Array[PhysicalBoneChainResource]:
    set(value):
        chain_setting_list = value
        if not skeleton:
            return
        for setting in chain_setting_list:
            if not setting:
                continue
            setting.callable_get_bone_name = skeleton.get_bone_name
            setting.callable_get_bone_name_hint = skeleton.get_concatenated_bone_names

var desired_gravity: float = 1.0

var skeleton: Skeleton3D
var physical_skeleton: PhysicalSkeleton
var leg_ik: IKModifier

var cached_state: PhysicsDirectBodyState3D


func editor_build_physical_skeleton() -> void:
    rebuild_physical_skeleton()

func _ready() -> void:
    skeleton = find_child('skeleton', false) as Skeleton3D
    if not skeleton:
        skeleton = Skeleton3D.new()
        skeleton.name = 'skeleton'
        add_child(skeleton, true)
        skeleton.owner = owner

    _construct_skeleton()

    physical_skeleton = skeleton.find_child('physical', false) as PhysicalSkeleton
    if not physical_skeleton:
        physical_skeleton = PhysicalSkeleton.new()
        physical_skeleton.name = 'physical'
        skeleton.add_child(physical_skeleton, true)
        physical_skeleton.owner = skeleton.owner
        # Sort it first
        skeleton.move_child(physical_skeleton, 0)

    leg_ik = skeleton.find_child('ik_modifier', false) as IKModifier
    if not leg_ik:
        leg_ik = IKModifier.new()
        leg_ik.name = 'ik_modifier'
        skeleton.add_child(leg_ik, true)
        leg_ik.owner = skeleton.owner

    physical_skeleton.skeleton = skeleton
    chain_setting_list = chain_setting_list

    if Engine.is_editor_hint():
        return

    physical_skeleton.active = true
    physical_skeleton.modification_processed.connect(_update_legs)
    leg_ik.modification_processed.connect(physical_skeleton.on_pose_finalized)

func _construct_skeleton() -> void:
    # Clear and build bone structure
    skeleton.clear_bones()

    var b_root: int = skeleton.add_bone('Root')
    skeleton.set_bone_rest(b_root,
        Transform3D(
            Quaternion.from_euler(Vector3(deg_to_rad(-90.0), 0.0, 0.0)),
            Vector3(0.0, 0.5, 0.4)
        )
    )

    var b_mid: int = skeleton.add_bone('MidSection')
    skeleton.set_bone_parent(b_mid, b_root)
    skeleton.set_bone_rest(b_mid,
        Transform3D(
            Basis.IDENTITY,
            Vector3(0.0, 0.4, 0.0)
        )
    )

    var b_fr_leg: int = skeleton.add_bone('FrontRightLeg')
    skeleton.set_bone_parent(b_fr_leg, b_mid)
    skeleton.set_bone_rest(b_fr_leg,
        Transform3D(
            Quaternion.from_euler(Vector3(0.0, 0.0, deg_to_rad(-45.0))),
            Vector3(0.0, 0.4, 0.0)
        )
    )

    var b_fr_femur: int = skeleton.add_bone('FrontRightFemur')
    skeleton.set_bone_parent(b_fr_femur, b_fr_leg)
    skeleton.set_bone_rest(b_fr_femur,
        Transform3D(
            Basis.IDENTITY,
            Vector3(0.0, 0.2, 0.0)
        )
    )

    var b_fr_tibia: int = skeleton.add_bone('FrontRightTibia')
    skeleton.set_bone_parent(b_fr_tibia, b_fr_femur)
    skeleton.set_bone_rest(b_fr_tibia,
        Transform3D(
            Quaternion.from_euler(Vector3(deg_to_rad(50.0), 0.0, 0.0)),
            Vector3(0.0, 0.2, 0.0)
        )
    )

    var b_fr_tarsus: int = skeleton.add_bone('FrontRightTarsus')
    skeleton.set_bone_parent(b_fr_tarsus, b_fr_tibia)
    skeleton.set_bone_rest(b_fr_tarsus,
        Transform3D(
            Quaternion.from_euler(Vector3(deg_to_rad(-90.0), 0.0, 0.0)),
            Vector3(0.0, 0.4, 0.0)
        )
    )

    skeleton.reset_bone_poses()

func rebuild_physical_skeleton() -> void:
    leg_ik.set_setting_count(0)

    var leg_ik_index: int = -1
    for chain_setting in chain_setting_list:
        physical_skeleton.remove_chain(chain_setting, true)
        var chain: PhysicalBoneChain3D = physical_skeleton.build_chain(chain_setting, Callable())
        if chain.is_ik_enabled:
            leg_ik_index += 1
            leg_ik.set_setting_count(leg_ik_index + 1)
            var target: Marker3D = skeleton.find_child('Target' + chain_setting.resource_name, false) as Marker3D
            if not target:
                target = Marker3D.new()
                target.name = 'Target' + chain_setting.resource_name
                skeleton.add_child(target, true)
                target.owner = skeleton.owner
                # Move to after physical skeleton modifier
                skeleton.move_child(target, physical_skeleton.get_index() + 1)
            chain.set_ik(leg_ik, leg_ik_index)
            leg_ik.setting_list[leg_ik_index].target_node = leg_ik.get_path_to(target)

    _update_body_mass.call_deferred()

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
    var leg_count: int = chain_setting_list.size()
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


var target_timer: float = 0.0
var target_shift: int = 0
## Simulate leg target movement
func _update_legs() -> void:
    if cached_state:
        target_timer += cached_state.step

        var shift: Vector3
        if target_shift == 1 and target_timer > 6.0:
            target_timer = 0.0
            target_shift = 0
            shift.z = 0.15
        elif target_shift == 0 and target_timer > 3.0:
            target_shift = 1
            shift.z = -0.15

        if not shift.is_zero_approx():
            for ik_setting in leg_ik.setting_list:
                var target: Node3D = leg_ik.get_node(ik_setting.target_node) as Node3D
                if not target:
                    continue
                target.position += shift

## Simplified force simulation, only damping and gravity. Matches the order of
## standard characters. Test bodies use a world joint to maintain position and
## orientation.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:

    # Apply damping forces immediately
    if not is_zero_approx(state.total_linear_damp):
        state.linear_velocity -= state.linear_velocity * state.total_linear_damp * state.step
    if not is_zero_approx(state.total_angular_damp):
        state.angular_velocity -= state.angular_velocity * state.total_angular_damp * state.step

    var gravity: Vector3 = state.total_gravity * desired_gravity

    ## begin update_ground()
    cached_state = state

    skeleton.advance(state.step, true)
    ## end update_ground()

    state.linear_velocity += gravity * state.step

    # If at low speed after all external forces are applied, zero out the velocity
    if state.linear_velocity.length_squared() < 1e-4:
        state.linear_velocity = Vector3.ZERO
    # Roughtly 0.5 degrees per seconds
    if state.angular_velocity.length_squared() < 7.62e-5:
        state.angular_velocity = Vector3.ZERO
