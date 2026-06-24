@tool
class_name IKModifier extends SkeletonModifier3D


const ChainResource = preload("uid://co33qil70ybm6")
const JointResource = preload("uid://c5ct6mxt0vyod")


## How many IK iterations to perform
@export_range(1, 10, 1, 'or_greater')
var iterations: int = 10

## Target minimum distance for IK
@export_range(0.0, 1.0, 0.001, 'or_greater')
var min_distance: float = 0.01

## How quickly IK is allowed to rotate a given joint
@export_range(0.01, 360.0, 0.01, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var angular_delta_limit: float = deg_to_rad(45.0)

## When enabled, this modifier will remember the output of the last IK result
## and start from that. The default behavior will start from the incoming pose.
@export var use_prior_work: bool = false:
    set(value):
        if use_prior_work and not value:
            _prior_work_map.clear()
        use_prior_work = value

@export var setting_list: Array[ChainResource]:
    set(value):
        setting_list = value
        # Initialize any nulls
        for index in range(setting_list.size()):
            if setting_list[index] != null:
                continue
            setting_list[index] = ChainResource.new()
            setting_list[index].resource_name = 'ChainResource'
        _connect_setting_list()
        if is_node_ready():
            _update_chain_list()

var chain_bone_list: Array[PackedInt32Array]
var skeleton: Skeleton3D

var _queued_joint_bone_names: bool = false

var _prior_work_map: Dictionary[int, Quaternion]


func _ready() -> void:
    skeleton = get_skeleton()
    _update_chain_list()

func _validate_property(property: Dictionary) -> void:
    if property.name == &'setting_list':
        _queue_update_joint_bone_names()

func get_nice_path(to: Node = null) -> NodePath:
    if not is_inside_tree():
        return NodePath("")

    if not to:
        to = self

    if not to.is_inside_tree():
        print_stack()
        push_error(
            (
                'get_nice_path() called with node not in the scene tree: "%s" %s'
            ) % [to.name, to]
        )
        return NodePath("")

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

func set_setting_count(count: int) -> void:
    var total: int = setting_list.size()
    if count == total:
        return
    setting_list.resize(count)
    setting_list = setting_list # Force setter call

func _enter_tree() -> void:
    _connect_setting_list()

func _exit_tree() -> void:
    _disconnect_setting_list()

func _connect_setting_list() -> void:
    for setting in setting_list:
        if not setting:
            continue
        if not setting.bone_changed.is_connected(_update_chain_list):
            setting.bone_changed.connect(_update_chain_list)
        if not setting.bone_changed.is_connected(_update_joint_bone_names):
            setting.bone_changed.connect(_update_joint_bone_names)
        if not setting.joint_list_changed.is_connected(_update_joint_bone_names):
            setting.joint_list_changed.connect(_update_joint_bone_names)

func _disconnect_setting_list() -> void:
    for setting in setting_list:
        if not setting:
            continue
        if setting.bone_changed.is_connected(_update_chain_list):
            setting.bone_changed.disconnect(_update_chain_list)
        if setting.bone_changed.is_connected(_update_joint_bone_names):
            setting.bone_changed.disconnect(_update_joint_bone_names)
        if setting.joint_list_changed.is_connected(_update_joint_bone_names):
            setting.joint_list_changed.disconnect(_update_joint_bone_names)

func _update_chain_list() -> void:
    var count: int = setting_list.size()
    chain_bone_list.resize(count)
    for index in range(count):
        var setting: ChainResource = setting_list[index]
        var root_bone: int = skeleton.find_bone(setting.root_bone)
        var end_bone: int = skeleton.find_bone(setting.end_bone)
        if skeleton:
            setting.bone_name_hint = skeleton.get_concatenated_bone_names()

        if root_bone == -1 or end_bone == -1:
            if not Engine.is_editor_hint():
                var missing_bone_str: PackedStringArray
                if root_bone == -1:
                    missing_bone_str.append('root bone "%s"' % setting.root_bone)
                if end_bone == -1:
                    missing_bone_str.append('end bone "%s"' % setting.end_bone)
                push_error(
                    (
                        'ChainResource for IK Modifier at %s cannot find bone '
                        + 'indices for %s on chain setting at index %d.'
                    ) % [get_nice_path(), ' and '.join(missing_bone_str), index]
                )
            chain_bone_list[index] = []
            continue

        var bone_list: PackedInt32Array
        while end_bone != root_bone and end_bone != -1:
            bone_list.append(end_bone)
            end_bone = skeleton.get_bone_parent(end_bone)
        bone_list.append(root_bone)
        bone_list.reverse()

        chain_bone_list[index] = bone_list

func _queue_update_joint_bone_names() -> void:
    if _queued_joint_bone_names:
        return
    _queued_joint_bone_names = true
    _update_joint_bone_names.call_deferred()

func _update_joint_bone_names() -> void:
    _queued_joint_bone_names = false
    for index in range(setting_list.size()):
        var setting: ChainResource = setting_list[index]
        if not setting:
            continue
        var bone_list: PackedInt32Array = chain_bone_list[index]
        var joint_count: int = setting.joint_list.size()
        for joint_index in range(bone_list.size()):
            if joint_index >= joint_count:
                break
            var joint: JointResource = setting.joint_list[joint_index]
            if not joint:
                continue
            joint.bone_name = skeleton.get_bone_name(bone_list[joint_index])

func _process_modification_with_delta(delta: float) -> void:
    var count: int = setting_list.size()
    var min_dist_sqr: float = min_distance * min_distance

    # Copy results of last work to skeleton pose
    if use_prior_work:
        for bone_idx in _prior_work_map:
            skeleton.set_bone_pose_rotation(bone_idx, _prior_work_map.get(bone_idx))
        _prior_work_map.clear()

    for index in range(count):
        var setting: ChainResource = setting_list[index]
        var target_node: Node3D = get_node_or_null(setting.target_node) as Node3D
        if not target_node:
            continue

        var target_position: Vector3 = skeleton.global_transform.affine_inverse() * target_node.global_position
        var bone_list: PackedInt32Array = chain_bone_list[index]
        var bone_count: int = bone_list.size()
        if bone_count == 0:
            continue

        # To limit rotation rate
        var cached_rotation_list: Array[Quaternion]
        cached_rotation_list.resize(bone_count)
        for i in range(bone_count):
            var bone_idx: int = bone_list[i]
            var bone_rotation: Quaternion = skeleton.get_bone_pose_rotation(bone_idx)

            # Apply rest correction
            if setting.rest_correction > 0.0:
                var rest: Quaternion = skeleton.get_bone_rest(bone_idx).basis.get_rotation_quaternion()
                var angle: float = bone_rotation.angle_to(rest)
                if angle > 1.7e-3:
                    bone_rotation = bone_rotation.slerp(rest, minf(1.0, (setting.rest_correction * delta) / angle))
                    skeleton.set_bone_pose_rotation(bone_idx, bone_rotation)

            cached_rotation_list[i] = bone_rotation

        var end_bone: int = bone_list[bone_count - 1]
        for n in range(iterations):
            if (
                target_position.distance_squared_to(skeleton.get_bone_global_pose(end_bone).origin)
                <= min_dist_sqr
            ):
                break

            _iterate_chain(bone_list, setting, target_position)

            # Must apply angle rate limit here with scaled delta, otherwise
            # iteration tends to look like it turns only one bone at a time
            var max_angle: float = 0.0
            for i in range(bone_count):
                var bone_idx: int = bone_list[i]
                var old_rot: Quaternion = cached_rotation_list[i]
                var new_rot: Quaternion = skeleton.get_bone_pose_rotation(bone_idx)
                var angle: float = old_rot.angle_to(new_rot)
                if angle > max_angle:
                    max_angle = angle

            for i in range(bone_count):
                var bone_idx: int = bone_list[i]
                var old_rot: Quaternion = cached_rotation_list[i]
                var new_rot: Quaternion = skeleton.get_bone_pose_rotation(bone_idx)
                var angle: float = old_rot.angle_to(new_rot)
                if angle > 1e-5:
                    new_rot = old_rot.slerp(
                        new_rot,
                        minf(
                            1.0,
                            (angular_delta_limit * delta) / angle
                        ) * (angle / max_angle)
                    )
                    skeleton.set_bone_pose_rotation(bone_idx, new_rot)

            skeleton.force_update_all_bone_transforms()

        if use_prior_work:
            for bone_idx in bone_list:
                _prior_work_map.set(bone_idx, skeleton.get_bone_pose_rotation(bone_idx))

func _iterate_chain(bone_list: PackedInt32Array, setting: ChainResource, target: Vector3) -> void:
    var bone_count: int = bone_list.size()
    var joint_count: int = bone_count - 1
    var end_bone: int = bone_list[bone_count - 1]

    # Go backwards from the last joint
    for joint in range(joint_count - 1, -1, -1):
        var joint_setting: JointResource = setting.joint_list[joint]
        var bone_idx: int = bone_list[joint]
        var parent_bone: int = skeleton.get_bone_parent(bone_idx)

        var bone_xform: Transform3D = skeleton.get_bone_global_pose(bone_idx)
        var bone_position: Vector3 = bone_xform.origin
        var bone_rotation: Quaternion = bone_xform.basis.get_rotation_quaternion()
        var end_bone_position: Vector3 = skeleton.get_bone_global_pose(end_bone).origin
        var parent_rotation: Quaternion

        if parent_bone != -1:
            parent_rotation = skeleton.get_bone_global_pose(parent_bone).basis.get_rotation_quaternion()

        var to_end: Vector3 = end_bone_position - bone_position
        var to_target: Vector3 = target - bone_position
        var rot_to_target: Quaternion = Quaternion(to_end, to_target)

        # Axis limitation
        var axis: Vector3 = Basis(bone_rotation)[joint_setting.rotation_axis]
        var rotated_axis: Vector3 = rot_to_target * axis
        var axis_correction_rot: Quaternion = Quaternion(rotated_axis, axis)
        rot_to_target = axis_correction_rot * rot_to_target

        var new_bone_rot: Quaternion = rot_to_target * bone_rotation

        # Rotation limitation
        if joint_setting.limitation_angle < TAU:
            var rest: Quaternion = skeleton.get_bone_rest(bone_idx).basis.get_rotation_quaternion()
            var origin: Quaternion = parent_rotation * rest * joint_setting.limitation_rotation_offset

            new_bone_rot = _limit_rotation(new_bone_rot, origin, joint_setting)

        skeleton.set_bone_pose_rotation(bone_idx, parent_rotation.inverse() * new_bone_rot)

func _limit_rotation(rot: Quaternion, origin: Quaternion, joint_setting: JointResource) -> Quaternion:
    var angle: float = rot.angle_to(origin)
    var max_angle: float = joint_setting.limitation_angle * 0.5
    if angle <= max_angle:
        return rot

    return origin.slerp(rot, max_angle / angle)
