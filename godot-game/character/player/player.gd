@tool
extends CharacterController


const LOOK_UP_MAX: float = deg_to_rad(89)
const LOOK_DOWN_MAX: float = deg_to_rad(-88)


@export_range(0.001, 10.0, 0.001, 'or_greater')
var max_speed: float = 4.9

@export_range(0.001, 5.0, 0.001, 'or_greater')
var walk_speed: float = 1.65

## Multiplier to slope speed changes when walking. Set to 0.0 to remove slope
## effect, 1.0 leaves it unchanged.
@export_range(0.0, 1.0, 0.001)
var walk_slope_effect: float = 0.0

## How much speed to jump off the ground with
@export_range(0.0, 10.0, 0.001)
var jump_power: float = 5.0

## How far down to crouch, applied as an offset to the set spring offset.
## Should be no more than the length of the spring.
@export_range(0.0, 1.0, 0.001, 'or_greater', 'suffix:m')
var crouch_offset: float = 0.39

## The safe fraction of the spring when the standing collider can be enabled.
## Math may be required to determine this value, but you can just do trial-and-error.
@export_range(0.0, 1.0, 0.001)
var crouch_safe_fraction: float = 0.6


@export_group('Input', 'input')

@export_subgroup('Look')
@export var input_look_speed: float = deg_to_rad(0.5)
@export var input_context_look: GUIDEMappingContext = preload("uid://buhmm20jgmwb5")
@export var input_action_look: GUIDEAction = preload("uid://chbhj3o2t8jvp")
@export var input_action_camera_toggle: GUIDEAction = preload("uid://b20e7e3b8jehd")

@export_subgroup('Move')
@export var input_context_move: GUIDEMappingContext = preload("uid://d1sotfpopn8ao")
@export var input_action_move: GUIDEAction = preload("uid://dqaca6xu7ac6a")
@export var input_action_walk: GUIDEAction = preload("uid://e6xtsr0uirai")
@export var input_action_jump: GUIDEAction = preload("uid://oru4dn30hyrs")
@export var input_action_crouch: GUIDEAction = preload("uid://cyig6itfyeel1")

@export_subgroup('Debug')
@export var input_debug_target_player: GUIDEAction = preload("uid://bfqs54sgopsvb")
@export var input_debug_target_position: GUIDEAction = preload("uid://u1oxg3mtiil8")
@export var input_debug_noclip: GUIDEAction = preload("uid://dlkderxbvtu4t")
@export var input_debug_freecam_context: GUIDEMappingContext = preload("uid://ckqnxijdumsoo")

@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false

## Show the GUIDE Debugger UI
@export var debug_guide_debugger: bool = false
@onready var guide_debugger: MarginContainer = %GuideDebugger


@onready var mesh_yaw: Node3D = %mesh_yaw

@onready var camera: Camera3D = %fp_camera
@onready var camera_pitch: Node3D = %fp_camera_pitch
@onready var camera_yaw: Node3D = %fp_camera_yaw

@onready var tp_camera_yaw: Node3D = %tp_camera_yaw
@onready var tp_camera_pitch: Node3D = %tp_camera_pitch
@onready var tp_camera_cast: ShapeCast3D = %tp_camera_cast
@onready var tp_camera: Camera3D = %tp_camera

@onready var collider_stand: CollisionShape3D = %collider_stand
@onready var collider_crouch: CollisionShape3D = %collider_crouch

## Toggle the camera mode
var camera_third_person: bool = false

## Toggle walk mode
var walk_mode: bool = false

## Toggle crouch mode
var crouch_mode: bool = false

## Toggle freecam mode
var freecam_mode: bool = false


var debug_targeting_player: bool = false


func _ready() -> void:
    super._ready()

    if not Engine.is_editor_hint():
        GUIDE.enable_mapping_context(input_context_look)
        GUIDE.enable_mapping_context(input_context_move)

func _process(_delta: float) -> void:
    if Engine.is_editor_hint():
        return

    camera_pitch.rotation.x = clampf(
            camera_pitch.rotation.x - input_action_look.value_axis_2d.y * input_look_speed,
            LOOK_DOWN_MAX, LOOK_UP_MAX
    )
    camera_yaw.rotation.y -= input_action_look.value_axis_2d.x * input_look_speed

    mesh_yaw.rotation.y = camera_yaw.rotation.y

    if input_action_camera_toggle.is_triggered():
        camera_third_person = not camera_third_person

    if camera_third_person != tp_camera.current:
        if camera_third_person:
            tp_camera.make_current()
        else:
            camera.make_current()

    if camera_third_person:
        tp_camera_pitch.rotation.x = camera_pitch.rotation.x
        tp_camera_yaw.rotation.y = camera_yaw.rotation.y

        var offset: Vector3 = tp_camera_cast.target_position * tp_camera_cast.get_closest_collision_safe_fraction()
        tp_camera.position = offset

    if input_debug_noclip.is_triggered():
        freecam_mode = not freecam_mode
        if freecam_mode:
            collider_crouch.disabled = true
            collider_stand.disabled = true
            spring.enabled = false
            force_ground_movement = false
            desired_gravity = 0.0
            crouch_mode = false
            desired_incline_effect = 0.0
            GUIDE.enable_mapping_context(input_debug_freecam_context, false, -1)
        else:
            # Crouch collider first
            collider_crouch.disabled = false
            spring.enabled = true
            force_ground_movement = true
            desired_gravity = 1.0
            GUIDE.disable_mapping_context(input_debug_freecam_context)

            if walk_mode:
                desired_incline_effect = walk_slope_effect
            else:
                desired_incline_effect = 1.0

    if input_action_walk.is_triggered():
        walk_mode = not walk_mode
        if not freecam_mode:
            if walk_mode:
                desired_incline_effect = walk_slope_effect
            else:
                desired_incline_effect = 1.0

    if (not freecam_mode) and input_action_jump.is_triggered():
        desired_jump_power = jump_power

    if (not freecam_mode) and input_action_crouch.is_triggered():
        crouch_mode = not crouch_mode

    if input_debug_target_player.is_triggered():
        var crawlers: Array[CrawlerCharacter]
        crawlers.assign(get_parent_node_3d().find_children('', 'CrawlerCharacter', false))
        for crawl in crawlers:
            crawl.target_position = position
        debug_targeting_player = true
    elif debug_targeting_player:
        var crawlers: Array[CrawlerCharacter]
        crawlers.assign(get_parent_node_3d().find_children('', 'CrawlerCharacter', false))
        for crawl in crawlers:
            crawl.target_position = Vector3.INF
        debug_targeting_player = false

    if crouch_mode:
        if collider_crouch.disabled:
            collider_crouch.disabled = false
            collider_stand.disabled = true
    elif (not freecam_mode) and collider_stand.disabled:
        # Test if we can switch to the stand collider using the shape_cast result
        if spring.get_closest_collision_safe_fraction() >= crouch_safe_fraction:
            collider_stand.disabled = false
            collider_crouch.disabled = true

    if guide_debugger.visible or guide_debugger.is_processing():
        if (not debug_enable) or (not debug_guide_debugger):
            guide_debugger.process_mode = Node.PROCESS_MODE_DISABLED
            guide_debugger.visible = false
    elif debug_enable and debug_guide_debugger:
        guide_debugger.process_mode = Node.PROCESS_MODE_INHERIT
        guide_debugger.visible = true

func _handle_input() -> void:
    if not is_node_ready():
        return

    desired_direction = input_action_move.value_axis_3d

    if freecam_mode:
        # From alternative freecam context
        if input_action_jump.is_triggered():
            desired_direction += Vector3.UP
        if input_action_crouch.is_triggered():
            desired_direction += Vector3.DOWN

    if desired_direction.length_squared() > 1e-3:
        desired_direction = desired_direction.normalized()

        if camera_third_person:
            if freecam_mode:
                desired_direction = tp_camera.global_basis * desired_direction
            else:
                desired_direction = tp_camera_yaw.global_basis * desired_direction
        elif freecam_mode:
            desired_direction = camera.global_basis * desired_direction
        else:
            desired_direction = camera_yaw.global_basis * desired_direction

        if freecam_mode:
            linear_damp = 1.0
            desired_speed = max_speed
            if walk_mode:
                desired_speed *= 0.5
        elif walk_mode or crouch_mode:
            desired_speed = walk_speed
        else:
            desired_speed = max_speed
    else:
        desired_speed = 0.0
        if freecam_mode:
            linear_damp = 10.0

    if input_action_jump.is_completed():
        desired_jump_power = 0.0

    if (not freecam_mode) and crouch_mode:
        desired_height_offset = -crouch_offset
    else:
        desired_height_offset = 0.0

    if input_debug_target_position.is_triggered():
        var active_camera: Camera3D = get_viewport().get_camera_3d()
        if active_camera:
            var query := PhysicsRayQueryParameters3D.new()
            query.from = active_camera.global_position
            query.to = query.from - active_camera.global_basis.z * 100.0
            query.collision_mask = collision_mask

            var hit: Dictionary = PhysicsServer3D.body_get_direct_state(get_rid()).get_space_state().intersect_ray(query)
            if hit:
                var crawlers: Array[CrawlerCharacter]
                crawlers.assign(get_parent_node_3d().find_children('', 'CrawlerCharacter', false))
                for crawl in crawlers:
                    crawl.target_position = hit.position
