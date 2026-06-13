class_name PhysicalBoneChain3D extends Node


@export_custom(
    PROPERTY_HINT_NONE,
    '',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var resource: PhysicalBoneChainResource

var is_valid: bool = false
var is_ik_enabled: bool = false
var is_ik_initialized: bool = false

var skeleton: Skeleton3D

var is_powered: bool = true
var is_any_part_broken: bool = false

var ik_setting_id: int = -1

var bone_list: PackedInt32Array
var part_list: Array[PhysicalBonePart3D]
var part_count: int


func _ready() -> void:
    validate()

## Returns a mapping of each part's related bone index to the array of joints.
## The provided arrays are read-only, and must be duplicated before modifying them
func get_bone_joint_map() -> Dictionary[int, Array]:
    var bone_joint_map: Dictionary[int, Array]

    for i in range(part_count):
        bone_joint_map.set(bone_list[i], part_list[i].get_joint_list())

    return bone_joint_map

func update() -> void:
    var power_active: bool = is_powered

    for index in range(part_count):
        var part: PhysicalBonePart3D = part_list[index]
        part.update(skeleton, bone_list[index])

        # Turn off part power when interrupted
        if part.is_powered and (not power_active):
            part.is_powered = false

        if part.is_power_interrupted:
            power_active = false

        if (not is_any_part_broken) and part.is_motor_broken:
            is_any_part_broken = true

    # TODO: I think this is still a good idea (June 13)
    # IDEA: Teleport IK end bone to real location? Maybe this will help IK

    # Call entire chain unpowered when the first part is interrupted and destroyed
    if is_powered and part_list[0].is_power_interrupted and part_list[0].is_motor_broken:
        is_powered = false

## Activates all rigid body parts of this chain
func activate(initial_state: PhysicsDirectBodyState3D) -> void:
    for i in range(part_count):
        var part: PhysicalBonePart3D = part_list[i]
        var bone: int = bone_list[i]

        # Teleport to bone
        part.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
        part.force_update_transform()

        # Copy state velocity
        var local_position: Vector3 = (part.global_position + part._cached_com) - initial_state.transform.origin
        part.linear_velocity = initial_state.get_velocity_at_local_position(local_position)
        part.angular_velocity = initial_state.angular_velocity

        part.activate()

## Disables all rigid body parts of this chain
func deactivate() -> void:
    for part in part_list:
        part.deactivate()

func init_ik(iterate_ik: IterateIK3D, setting_index: int) -> void:
    is_ik_initialized = true
    # TODO

func setup_velocity() -> void:
    for index in range(part_count):
        var part: PhysicalBonePart3D = part_list[index]
        part.setup_velocity(skeleton, bone_list[index])

func solve_velocity(iteration_count: int, delta: float) -> void:

    for i in range(iteration_count):
        # NOTE: I don't want to write two range loops, so I just reimplemented
        #       the range loop as a while loop
        var index: int
        var step: int

        if i % 2 == 0:
            index = -1
            step = 1
        else:
            index = part_count
            step = -1

        var count: int = part_count
        var had_impulse: bool = false
        while count > 0:
            count -= 1
            index += step

            var part: PhysicalBonePart3D = part_list[index]

            # The rest will be unpowered when iterating forward, so break early
            if not part.is_powered:
                if step > 0:
                    break
                continue

            # The motor itself may be effectively destroyed, so no need to solve
            if part.is_motor_broken:
                continue

            # TODO: given the motor velocities and rigid body state, calculate
            #       an angle error for this part

            var applied_impulse: bool = part.solve_motor_velocity(delta)
            had_impulse = had_impulse || applied_impulse

        if not had_impulse:
            break

func validate() -> void:
    is_valid = false
    is_ik_enabled = false
    skeleton = null
    part_list.clear()
    bone_list.clear()
    part_count = 0

    var found_skeleton: Skeleton3D = null
    var next_parent: Node = get_parent()
    while next_parent != null:
        if next_parent is Skeleton3D:
            found_skeleton = next_parent
            break
        next_parent = next_parent.get_parent()

    if not found_skeleton:
        push_error(
            (
                'PhysicalBoneChain3D %s must have a Skeleton3D as a direct ancestor when added to '
                + 'the scene tree. You must use the build method from a PhysicalSkeleton to create '
                + 'these nodes.'
            ) % get_path()
        )
        return

    if not resource:
        push_error(
            (
                'PhysicalBoneChain3D %s does not have a resource assigned to it. '
                + 'You must use the build method from a PhysicalSkeleton to create these nodes.'
            ) % get_path()
        )
        return

    if resource.unique_id == -1:
        push_error(
            (
                'PhysicalBoneChain3D %s internal resource named %s at %s has not had its unique id generated yet. '
                + 'You must use the build method from a PhysicalSkeleton to create these nodes.'
            ) % [get_path(), resource.resource_name, resource.resource_path]
        )
        return

    var new_part_count: int = resource.part_list.size()
    if new_part_count == 0:
        push_error(
            (
                'PhysicalBoneChain3D %s (resource named %s at %s) has an empty part list, this '
                + 'should be avoided by removing the chain or giving it parts.'
            ) % [get_path(), resource.resource_name, resource.resource_path]
        )
        return

    # Ensure all parts are non-null
    for index in range(new_part_count):
        var part: PhysicalBonePartResource = resource.part_list[index]
        if not part:
            push_error(
                (
                    'PhysicalBoneChain3D %s (resource named %s at %s) is missing a part at index %d, null found.'
                ) % [get_path(), resource.resource_name, resource.resource_path, index]
            )
            return

    var new_bone_list: PackedInt32Array = resource.get_bone_list(found_skeleton)
    if new_bone_list.size() != new_part_count:
        push_error(
            (
                'PhysicalBoneChain3D %s (resource named %s at %s) failed to obtain bone ids for part list. '
                + 'Needed %d ids, but got %d'
            ) % [get_path(), resource.resource_name, resource.resource_path, new_part_count, new_bone_list.size()]
        )
        return

    var children_part_list: Array[PhysicalBonePart3D]
    children_part_list.assign(find_children('', 'PhysicalBonePart3D'))

    var indexed_part_list: Array[PhysicalBonePart3D]
    indexed_part_list.resize(new_part_count)
    for part in children_part_list:
        if part.part_index == -1:
            push_error(
                (
                    'PhysicalBoneChain3D %s found a misconfigured child PhysicalBonePart3D %s, missing '
                    + 'a part index. '
                    + 'You must use the build method from a PhysicalSkeleton to create these nodes.'
                ) % [get_path(), part.get_path()]
            )
            return

        if part.part_index >= new_part_count:
            push_error(
                (
                    'PhysicalBoneChain3D %s found an extra child PhysicalBonePart3D %s, part index '
                    + 'is greater than the size of the resource part list. '
                    + 'You should rebuild from a PhysicalSkeleton, or add the missing part to the '
                    + 'resource named %s at %s.'
                ) % [get_path(), part.get_path(), resource.resource_name, resource.resource_path]
            )
            return

        if indexed_part_list[part.part_index] != null:
            push_error(
                (
                    'PhysicalBoneChain3D %s found two child PhysicalBonePart3D which share the same '
                    + 'part index, nodes are %s and %s.'
                    + 'You should rebuild from a PhysicalSkeleton, delete the extra PhysicalBonePart3D, '
                    + 'or add the missing part to the resource named %s at %s.'
                ) % [
                    get_path(), part.get_path(), indexed_part_list[part.part_index].get_path(),
                    resource.resource_name, resource.resource_path
                ]
            )
            return

        if not part.resource:
            push_error(
                (
                    'PhysicalBoneChain3D %s found child PhysicalBonePart3D %s which is missing a '
                    + 'resource.'
                    + 'You must use the build method from a PhysicalSkeleton to create these nodes.'
                ) % [get_path(), part.get_path()]
            )
            return

        if part.resource != resource.part_list[part.part_index]:
            push_error(
                (
                    'PhysicalBoneChain3D %s found misconfigured child PhysicalBonePart3D %s, the '
                    + 'internal resource does not match the chain resource definition named %s at %s. '
                    + 'You should rebuild from a PhysicalSkeleton to fix the node.'
                ) % [get_path(), part.get_path(), resource.resource_name, resource.resource_path]
            )
            return

        indexed_part_list[part.part_index] = part

    # Check for ik enabled parts
    for index in range(new_part_count):
        if part_list[index].resource.ik_enabled:
            is_ik_enabled = true
            break

    is_valid = true
    skeleton = found_skeleton
    bone_list = new_bone_list
    part_list = indexed_part_list
    part_count = new_part_count
