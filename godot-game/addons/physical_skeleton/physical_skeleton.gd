## Maintains a system made of joints and rigid bodies for a skeleton, giving it
## physical reactions to other objects in the world
@tool
class_name PhysicalSkeleton extends SkeletonModifier3D


const META_OWNED: StringName = &'_physical_skeleton_owned'
const META_CHAIN_ROOT: StringName = &'_physical_chain_root'
const META_CHAIN_RESOURCE_ID: StringName = &'_physical_chain_resource_id'


@export_tool_button('Update Joints', 'Generic6DOFJoint3D')
var _btn_update_joints = editor_update_joints


## How many copies to create of the first joints in the chain. Set to zero to
## disable copies.
@export_range(0, 10, 1, 'or_greater')
var first_joint_copies: int = 3

## How many copies to create of other joints in the chain. Set to zero to
## disable copies
@export_range(0, 10, 1, 'or_greater')
var joint_copies: int = 2

## Length to spread the joints on the rotation axis
@export_range(0.0, 0.2, 0.001)
var joint_copy_width: float = 0.01


@export_group('Spring Calculator', 'calc_spring')

@export_custom(PROPERTY_HINT_RANGE, '0.001,100.0,0.001,or_greater,suffix:kg', PROPERTY_USAGE_EDITOR)
var calc_spring_effective_mass: float = 4.0:
    set(value):
        calc_spring_effective_mass = value
        editor_update_spring_calculator()

@export_custom(PROPERTY_HINT_RANGE, '0.001,100.0,0.001,or_greater,suffix:Hz', PROPERTY_USAGE_EDITOR)
var calc_spring_frequency: float = 1.2:
    set(value):
        calc_spring_frequency = value
        editor_update_spring_calculator()

@export_custom(PROPERTY_HINT_RANGE, '0.0,1.0,0.001', PROPERTY_USAGE_EDITOR)
var calc_spring_damping_ratio: float = 0.5:
    set(value):
        calc_spring_damping_ratio = value
        editor_update_spring_calculator()

@export_custom(
    PROPERTY_HINT_RANGE,
    '0.0,1.0,0.001,or_greater,hide_control',
    PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR
)
var calc_spring_stiffness: float = 0.0

@export_custom(
    PROPERTY_HINT_RANGE,
    '0.0,1.0,0.001,or_greater,hide_control',
    PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR
)
var calc_spring_damping: float = 0.0


@export_group('Frequency Calculator', 'calc_freq')

@export_custom(PROPERTY_HINT_RANGE, '0.001,100.0,0.001,or_greater', PROPERTY_USAGE_EDITOR)
var calc_freq_stiffness: float = 4.0:
    set(value):
        calc_freq_stiffness = value
        editor_update_frequency_calculator()

@export_custom(PROPERTY_HINT_RANGE, '0.001,100.0,0.001,or_greater,suffix:Hz', PROPERTY_USAGE_EDITOR)
var calc_freq_frequency: float = 1.2:
    set(value):
        calc_freq_frequency = value
        editor_update_frequency_calculator()

@export_custom(PROPERTY_HINT_RANGE, '0.0,1.0,0.001', PROPERTY_USAGE_EDITOR)
var calc_freq_damping_ratio: float = 0.5:
    set(value):
        calc_freq_damping_ratio = value
        editor_update_frequency_calculator()

@export_custom(
    PROPERTY_HINT_RANGE,
    '0.0,1.0,0.001,or_greater,hide_control',
    PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR
)
var calc_freq_damping: float = 0.0


## The skeleton driving the joints
var skeleton: Skeleton3D
## The main body of the skeleton
var main_body: RigidBody3D

var _bone_part_map: Dictionary[int, PhysicalBonePart3D]
## Node holding all the chain nodes
var _chain_node_root: Node
## Map chain uids to chain nodes
var _chain_node_map: Dictionary[int, PhysicalBoneChain3D]


var initialized: bool = false
var has_bodies: bool = false
var bodies_active: bool = false

var _cached_attachments: Array[ModifierBoneTarget3D] = []
var cached_delta: float

var chain_list: Array[PhysicalBoneChain3D]
var _setup_queued: bool = false


func editor_update_joints() -> void:
    EditorInterface.get_editor_toaster().push_toast(
            'Functionality not implemented! TODO!',EditorToaster.SEVERITY_INFO
    )

func editor_update_spring_calculator() -> void:
    # Stiffness and damping force calculation from Jolt's frequency/ damping ratio
    var omega: float = TAU * calc_spring_frequency
    calc_spring_stiffness = calc_spring_effective_mass * omega * omega
    calc_spring_damping = 2.0 * calc_spring_effective_mass * calc_spring_damping_ratio * omega

func editor_update_frequency_calculator() -> void:
    # Stiffness and damping force calculation from Jolt's frequency/ damping ratio
    var omega: float = TAU * calc_freq_frequency
    var effective_mass: float = calc_freq_stiffness / (omega * omega)
    calc_freq_damping = 2.0 * effective_mass * calc_freq_damping_ratio * omega

func _ready() -> void:
    _setup()

func get_nice_path(to: Node = null) -> NodePath:
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

func queue_setup() -> void:
    if _setup_queued:
        return
    _setup_queued = true
    _setup.call_deferred()

func _setup() -> void:
    _setup_queued = false

    main_body = _find_main_body()
    if not main_body:
        push_error('PhysicalSkeleton could not find a primary RigidBody3D!')
        return

    var chain_root: Node = get_chain_node_root()
    if not chain_root:
        push_error(
            'PhysicalSkeleton could not find the chain root node, it must be built first. '
            + 'Only PhysicalBoneChain3D created by this PhysicalSkeleton that are in the '
            + 'chain root node can be loaded. You may organize the nodes however you want, '
            + 'as long as they exist somewhere in the chain root node.'
        )
        return

    chain_list.assign(chain_root.find_children('', 'PhysicalBoneChain3D'))
    if chain_list.size() == 0:
        push_error(
            (
                'PhysicalSkeleton found no PhysicalBoneChain3D within the chain '
                + 'root %s. Only chains within this root node can be loaded, '
                + 'please move the nodes into this root or rebuild the chain. '
                + 'You can organize them however you  want, as long as they are '
                + 'somewhere in the chain root node.'
            ) % get_nice_path(chain_root)
        )
        return

    _chain_node_map = {}
    _bone_part_map = {}

    for chain in chain_list:
        # HACK: I hate await, but without making gaurantees about the order of
        #       the chain root relative to this node, we must await them
        if not chain.is_node_ready():
            await chain.ready
        _bone_part_map.merge(chain.get_bone_part_map(), true)

        var id: int = chain.get_meta(META_CHAIN_RESOURCE_ID, ResourceUID.INVALID_ID)
        if id != ResourceUID.INVALID_ID:
            _chain_node_map.set(id, chain)

    _chain_node_map.make_read_only()
    _bone_part_map.make_read_only()

func _process_modification_with_delta(delta: float) -> void:
    if not initialized:
        setup_body()
        initialized = true

    if not has_bodies:
        return

    if active:
        if not bodies_active:
            activate_bodies()
    else:
        if bodies_active:
            deactivate_bodies()
        return

    cached_delta = delta

    for chain in chain_list:
        if not chain.is_valid:
            continue
        chain.update()

func activate_bodies() -> void:
    # Inherit velocity of main body
    var main_body_state := PhysicsServer3D.body_get_direct_state(main_body.get_rid())

    for chain in chain_list:
        chain.activate(main_body_state)

    bodies_active = true

func deactivate_bodies() -> void:
    for chain in chain_list:
        chain.deactivate()

    bodies_active = false

## Call this when the skeleton pose is ready to be targeted using joint motors.
## This modifier must have processed early enough to copy the physical joint
## rotations onto the skeleton pose, and save the initial rotations, so it can
## correctly target what changed in the pose.
func on_pose_finalized() -> void:
    if not bodies_active:
        return

    const ITERATIONS: int = 1
    for chain in chain_list:
        if (not chain.is_valid) or (not chain.is_powered):
            continue
        chain.setup_velocity()
        chain.solve_velocity(ITERATIONS, cached_delta)

func get_bone_part_map() -> Dictionary[int, PhysicalBonePart3D]:
    return _bone_part_map

func get_chain_node_root() -> Node:
    if _chain_node_root:
        # Check that it is still in the scene tree
        if not _chain_node_root.is_inside_tree():
            _chain_node_root.queue_free()
            _chain_node_root = null
        else:
            return _chain_node_root

    if not skeleton:
        skeleton = _find_skeleton()

    var skel_children: Array[Node] = skeleton.get_children()
    for node in skeleton.get_children():
        if node.get_meta(META_CHAIN_ROOT, false):
            _chain_node_root = node
            return _chain_node_root

    # Scan all nested children
    for node in skel_children:
        for nested in node.find_children('*'):
            if node.get_meta(META_CHAIN_ROOT, false):
                _chain_node_root = node
                return _chain_node_root

    return null

func build_chain(
    chain_resource: PhysicalBoneChainResource,
    custom_joint_builder: Callable
) -> PhysicalBoneChain3D:
    if not chain_resource:
        push_error(
            (
                'PhysicalSkeleton at %s method `build_chain()` called without a '
                + 'chain resource. Returning false.'
            ) % get_nice_path()
        )
        return null

    # Generate the custom unique id if needed
    if chain_resource.unique_id == ResourceUID.INVALID_ID:
        chain_resource.generate_unique_id()

        # It can fail if the resource isn't saved, or doesn't specify bones
        if chain_resource.unique_id == ResourceUID.INVALID_ID:
            push_error(
                (
                    'PhysicalSkeleton at %s method `build_chain()` called with an '
                    + 'invalid chain resource. Errors should be above. Returning false.'
                ) % get_nice_path()
            )
            return null

        # Save resource immediately
        ResourceSaver.save(chain_resource)

    # Create the root if it doesn't exist yet
    var chain_root: Node = get_chain_node_root()
    if not chain_root:
        chain_root = Node.new()
        chain_root.name = 'ChainRootNode'
        chain_root.set_meta(META_CHAIN_ROOT, true)
        skeleton.add_child(chain_root, true)
        chain_root.owner = owner
        queue_setup()

    var chain := PhysicalBoneChain3D.new()
    chain.set_meta(&'_custom_type_script', ResourceUID.id_to_text(ResourceLoader.get_resource_uid((chain.get_script() as Script).resource_path)))
    chain.resource = chain_resource
    chain.set_meta(META_CHAIN_RESOURCE_ID, chain.resource.unique_id)
    chain.name = chain.resource.resource_name

    chain._skip_ready = true
    chain_root.add_child(chain, true)
    chain.owner = chain_root.owner

    # Skeleton is determined by the _ready() method, but since we skip that,
    # we have to provide it here before calling build_chain()
    chain.skeleton = skeleton
    var success: bool = chain.build_chain(main_body, custom_joint_builder)
    if not success:
        chain_root.remove_child(chain)
        return null

    queue_setup()
    return chain

func prepare_custom_joints(chain_resource: PhysicalBoneChainResource, custom_joint_callable: Callable) -> bool:
    if not main_body:
        push_error(
            (
                'PhysicalSkeleton at %s has no main body, unable to load chain resources at this time'
            ) % get_nice_path()
        )
        return false

    if not chain_resource:
        push_error(
            (
                'PhysicalSkeleton at %s method `prepare_custom_joints()` called '
                + 'without a chain resource. Returning false.'
            ) % get_nice_path()
        )
        return false

    if not custom_joint_callable.is_valid():
        push_error(
            (
                'PhysicalSkeleton at %s method `prepare_custom_joints()` called '
                + 'without a valid custom joint callable. Returning false.'
            ) % get_nice_path()
        )
        return false

    var chain: PhysicalBoneChain3D = _chain_node_map.get(chain_resource.unique_id)
    if not chain:
        push_error(
            (
                'PhysicalSkeleton at %s could not find a chain using the resource named %s at %s. '
                + 'Consider rebuilding the chain.'
            ) % [get_nice_path(), chain_resource.resource_name, chain_resource.resource_path]
        )
        return false

    if not chain.is_valid:
        push_error(
            (
                'PhysicalBoneChain3D at %s is marked invalid, there should be errors above.'
            ) % [chain.get_nice_path()]
        )
        return false

    return chain.prepare_custom_joints(custom_joint_callable)

func setup_body() -> void:
    skeleton = get_skeleton()
    if not skeleton:
        push_error('PhysicalSkeleton could not find a skeleton!')
        return

    if Engine.is_editor_hint():
        return

    # Collect bone joint mappings for priority assignment
    var bone_joint_map: Dictionary[int, Array] = {}

    # Ensure collision exceptions for parts that initially intersect the main body
    var main_body_rid: RID = main_body.get_rid()
    var main_body_state := PhysicsServer3D.body_get_direct_state(main_body_rid)
    var space := main_body_state.get_space_state()
    var query := PhysicsShapeQueryParameters3D.new()
    query.collision_mask = PhysicsServer3D.body_get_collision_layer(main_body_rid)

    # Process chains
    for chain in chain_list:
        var chain_bone_joint_map: Dictionary[int, Array] = chain.get_bone_joint_map()

        for bone_idx in chain_bone_joint_map:
            if bone_joint_map.has(bone_idx):
                push_error(
                    (
                        'PhysicalSkeleton found duplicated PhysicalBoneChain3D %s, '
                        + 'it references the bone %s, which is already managed by '
                        + 'another chain. Please delete the duplicated node, or '
                        + 'rebuild the chains.'
                    ) % [chain.name, skeleton.get_bone_name(bone_idx)]
                )
                return

        bone_joint_map.assign(chain_bone_joint_map)

        # Process parts

        for part in chain.part_list:
            _setup_chain_part(part, space, query)

    var joint_priority_map: Dictionary = _calculate_joint_priority(bone_joint_map)

    # Reverse priorities so earlier joints solve later, improving chain accuracy
    var max_priority: int = joint_priority_map.get(&'priority')
    for priority in joint_priority_map:
        if priority is not int:
            continue
        var joint_list: Array[Joint3D]
        joint_list.assign(joint_priority_map.get(priority))
        for joint in joint_list:
            # NOTE: i cannot demonstrate that this is better than not reversing priority...
            #       but logically it should as the first iteration will send lower leg
            #       impulses straight to the main body, rather than lag by N+ iterations
            joint.solver_priority = max_priority - priority

    # Initially disable bodies
    deactivate_bodies()

    has_bodies = true

## Set up part collision exceptions
func _setup_chain_part(
        part: PhysicalBonePart3D,
        space: PhysicsDirectSpaceState3D,
        query: PhysicsShapeQueryParameters3D
) -> void:
    # Check current exceptions, may already include main body
    for excepted in part.get_collision_exceptions():
        if excepted == main_body:
            return

    # If the main body is intersecting this body, ensure it has a collision
    # exception. This can happen when joint bodies exist fully contained in
    # the main body, causing the next joint to not add the exception by default.

    var main_body_rid: RID = main_body.get_rid()
    var body_rid: RID = part.get_rid()
    var intersects_main_body: bool = false
    for body_shape in range(PhysicsServer3D.body_get_shape_count(body_rid)):
        var body_shape_rid: RID = PhysicsServer3D.body_get_shape(body_rid, body_shape)
        var shape_xform: Transform3D = PhysicsServer3D.body_get_shape_transform(body_rid, body_shape)

        query.shape_rid = body_shape_rid
        query.transform = part.global_transform * shape_xform

        var intersections: Array[Dictionary] = space.intersect_shape(query, 8)
        for hit in intersections:
            if hit.rid == main_body_rid:
                intersects_main_body = true
                break

        if intersects_main_body:
            break

    if not intersects_main_body:
        return

    print(
        (
            'PhysicalBonePart3D %s initially intersects %s, adding exception'
        ) % [part.name, main_body.name]
    )
    part.add_collision_exception_with(main_body)
    main_body.add_collision_exception_with(part)

## Travels up the scene tree until it finds the first RigidBody3D
func _find_main_body() -> RigidBody3D:
    var parent: Node = get_parent()
    while parent:
        if parent is RigidBody3D:
            return parent
        parent = parent.get_parent()
    return null

func _find_skeleton() -> Skeleton3D:
    var parent: Node = get_parent()
    while parent:
        if parent is Skeleton3D:
            return parent
        parent = parent.get_parent()
    return null

func _calculate_joint_priority(bone_joint_map: Dictionary[int, Array]) -> Dictionary:
    var joint_priority_map: Dictionary
    var search: PackedInt32Array = [0]
    var expand: PackedInt32Array = []
    var next: PackedInt32Array = []
    var priority: int = 0

    var joint_collection: Array[Array]
    var max_priority: int = 0
    while search.size() > 0:
        for bone_idx in search:
            if bone_joint_map.has(bone_idx):
                var found_joints: Array[Joint3D]
                found_joints.assign(bone_joint_map.get(bone_idx))
                if found_joints.size() == 0:
                    expand.append(bone_idx)
                    continue

                joint_collection.append(found_joints)
                max_priority = maxi(max_priority, found_joints.size())
                next.append(bone_idx)
                continue
            expand.append(bone_idx)

        if expand.size() > 0:
            search.clear()
            for bone_idx in expand:
                search.append_array(skeleton.get_bone_children(bone_idx))
            expand.clear()
            continue

        # Add all joints to this layer
        for joint_list in joint_collection:
            var p: int = priority
            for joint in joint_list:
                if not joint_priority_map.has(p):
                    joint_priority_map.set(p, Array())
                joint_priority_map.get(p).append(joint)
                p += 1
        joint_collection.clear()
        priority += max_priority
        max_priority = 0

        search.clear()
        for bone_idx in next:
            search.append_array(skeleton.get_bone_children(bone_idx))
        next.clear()

    joint_priority_map.set(&'priority', priority)
    return joint_priority_map
