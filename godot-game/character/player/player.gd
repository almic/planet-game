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


func _ready() -> void:
    GUIDE.enable_mapping_context(input_context_look)
    GUIDE.enable_mapping_context(input_context_move)

func _process(delta: float) -> void:
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

    if input_action_walk.is_triggered():
        walk_mode = not walk_mode
        if walk_mode:
            desired_incline_effect = walk_slope_effect
        else:
            desired_incline_effect = 1.0

    if input_action_jump.is_triggered():
        desired_jump_power = jump_power

    if input_action_crouch.is_triggered():
        crouch_mode = not crouch_mode

    if crouch_mode:
        if collider_crouch.disabled:
            collider_crouch.disabled = false
            collider_stand.disabled = true
    elif collider_stand.disabled:
        # Test if we can switch to the stand collider using the shape_cast result
        if shape_cast.get_closest_collision_safe_fraction() >= crouch_safe_fraction:
            collider_stand.disabled = false
            collider_crouch.disabled = true

func _handle_input() -> void:
    if not is_node_ready():
        return

    if input_action_move.value_axis_3d.length_squared() > 1e-3:
        desired_direction = input_action_move.value_axis_3d.normalized()
        if camera_third_person:
            desired_direction = tp_camera_yaw.global_basis * desired_direction
        else:
            desired_direction = camera_yaw.global_basis * desired_direction
        if walk_mode or crouch_mode:
            desired_speed = walk_speed
        else:
            desired_speed = max_speed
    else:
        desired_speed = 0.0

    if input_action_jump.is_completed():
        desired_jump_power = 0.0

    if crouch_mode:
        desired_height_offset = -crouch_offset
    else:
        desired_height_offset = 0.0
