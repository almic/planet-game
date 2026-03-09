extends CharacterController


const LOOK_UP_MAX: float = deg_to_rad(89)
const LOOK_DOWN_MAX: float = deg_to_rad(-88)


@export_group('Input', 'input')

@export_subgroup('Look')
@export var input_look_speed: float = deg_to_rad(0.5)
@export var input_context_look: GUIDEMappingContext = preload("uid://buhmm20jgmwb5")
@export var input_action_look: GUIDEAction = preload("uid://chbhj3o2t8jvp")
@export var input_action_camera_toggle: GUIDEAction = preload("uid://b20e7e3b8jehd")

@export_subgroup('Move')
@export var input_context_move: GUIDEMappingContext = preload("uid://d1sotfpopn8ao")
@export var input_action_move: GUIDEAction = preload("uid://dqaca6xu7ac6a")


@onready var mesh_yaw: Node3D = %mesh_yaw

@onready var camera: Camera3D = %fp_camera
@onready var camera_pitch: Node3D = %fp_camera_pitch
@onready var camera_yaw: Node3D = %fp_camera_yaw

@onready var tp_camera_yaw: Node3D = %tp_camera_yaw
@onready var tp_camera_pitch: Node3D = %tp_camera_pitch
@onready var tp_camera_cast: ShapeCast3D = %tp_camera_cast
@onready var tp_camera: Camera3D = %tp_camera

## Toggle the camera mode
var camera_third_person: bool = false


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


func _handle_input() -> void:
    if input_action_move.value_axis_3d.length_squared() > 1e-3:
        desired_velocity = camera.global_basis * input_action_move.value_axis_3d.normalized() * 4.0
    else:
        desired_velocity = Vector3.ZERO
