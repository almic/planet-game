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

## The safe length of the spring when the standing collider can be enabled.
@export_range(0.0, 1.0, 0.001)
var crouch_safe_length: float = 0.45


@export_group('Camera', 'camera')
@export var camera_main: Camera3D
@export var camera_root: Node3D
@export var camera_pitch: Node3D
@export var camera_cast: ShapeCast3D
@export var camera_interaction_ray: InteractionRay
@export_range(0.1, 2.0, 0.01, 'or_greater', 'suffix:s')
var camera_interpolation_time: float = 1.0
@export_exp_easing() var camera_interpolation_curve: float = -2.0


@export_group('Input', 'input')

@export_subgroup('Camera', 'input_camera')
@export var input_camera_context: GUIDEMappingContext = preload("uid://buhmm20jgmwb5")
@export_range(0.01, 2.0, 0.01, 'or_greater', 'radians_as_degrees')
var input_camera_look_speed: float = deg_to_rad(0.5)
@export var input_camera_look: GUIDEAction = preload("uid://chbhj3o2t8jvp")
@export var input_camera_toggle: GUIDEAction = preload("uid://b20e7e3b8jehd")

@export_subgroup('Movement', 'input_movement')
@export var input_movement_context: GUIDEMappingContext = preload("uid://d1sotfpopn8ao")
@export var input_movement_move: GUIDEAction = preload("uid://dqaca6xu7ac6a")
@export var input_movement_walk: GUIDEAction = preload("uid://e6xtsr0uirai")
@export var input_movement_jump: GUIDEAction = preload("uid://oru4dn30hyrs")
@export var input_movement_crouch: GUIDEAction = preload("uid://cyig6itfyeel1")

@export_subgroup('Action', 'input_action')
@export var input_action_interact: GUIDEAction = preload("uid://ckxv2u04ey181")
@export var input_action_shoot: GUIDEAction = preload("uid://dcni2sonyj3o6")

@export_subgroup('Vehicle', 'input_vehicle')
@export var input_vehicle_context: GUIDEMappingContext = preload("uid://8kiw4h7gebrd")
@export var input_vehicle_accelerate: GUIDEAction = preload("uid://c7o1q8uj6dome")
@export var input_vehicle_brake: GUIDEAction = preload("uid://c01llixsqkl6y")
@export var input_vehicle_exit: GUIDEAction = preload("uid://c8ci36bxyiklw")
@export var input_vehicle_handbrake: GUIDEAction = preload("uid://1jsloi57gq2a")
@export var input_vehicle_reverse: GUIDEAction = preload("uid://iff0s084mt2p")
@export var input_vehicle_steer: GUIDEAction = preload("uid://igesxxow0qge")


## NOTE: fixes weird editor bug that puts the next export in the above group...
@export_subgroup('')

@export_subgroup('Debug', 'input_debug')
@export var input_debug_target_position: GUIDEAction = preload("uid://u1oxg3mtiil8")
@export var input_debug_target_player: GUIDEAction = preload("uid://bfqs54sgopsvb")
@export var input_debug_noclip: GUIDEAction = preload("uid://dlkderxbvtu4t")
@export var input_debug_freecam_context: GUIDEMappingContext = preload("uid://ckqnxijdumsoo")

@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false

## Show the GUIDE Debugger UI
@export var debug_guide_debugger: bool = false
@onready var guide_debugger: MarginContainer = %GuideDebugger

@export var debug_vehicle_debugger: bool = false
@onready var vehicle_debugger: GridContainer = %VehicleDebugger
@onready var vehicle_debug_gear_value: Label = %GearValue
@onready var vehicle_debug_speed_value: Label = %SpeedValue
@onready var vehicle_debug_rpm_value: Label = %RPMValue

@onready var mesh_yaw: Node3D = %mesh_yaw

@onready var collider_stand: CollisionShape3D = %collider_stand
@onready var collider_crouch: CollisionShape3D = %collider_crouch

var grenade: PackedScene = preload("uid://bbk6ygeifp3v3")

## Toggle the camera mode
var camera_third_person: bool = false:
    set(value):
        if camera_third_person != value:
            camera_third_person = value
            camera_interpolation = clampf(1.0 - camera_interpolation, 0.0, 1.0)

## Interpolation from first person to third person camera locations. Set to zero
## to begin the animation, toggles to (1.0 - X) when switching camera modes.
var camera_interpolation: float = 0.0

## Toggle walk mode
var walk_mode: bool = false

## Toggle crouch mode
var crouch_mode: bool = false

## Toggle freecam mode
var freecam_mode: bool = false

## Tracker for shooting, temporary, should be removed when a weapon system is
## implemented.
var can_shoot: bool = true

## When true, wait for vehicle exit/ interact completion before allowing vehicle
## entry/ exiting, preventing instant re-entry or exiting.
var vehicle_entry_wait: bool = false

## The player should exit the vehicle on the next physics tick
var vehicle_do_exit: bool = false


var debug_targeting_player: bool = false


func _ready() -> void:
    super._ready()

    if not Engine.is_editor_hint():
        GUIDE.enable_mapping_context(input_camera_context)
        GUIDE.enable_mapping_context(input_movement_context)

        InputManager.allow_mouse_capture = false
        InputManager.allow_pause_on_exit = false
        InputManager.pause()

func _process(delta: float) -> void:
    if Engine.is_editor_hint():
        return

    camera_pitch.rotation.x = clampf(
        camera_pitch.rotation.x - input_camera_look.value_axis_2d.y * input_camera_look_speed,
        LOOK_DOWN_MAX, LOOK_UP_MAX
    )
    camera_root.rotation.y -= input_camera_look.value_axis_2d.x * input_camera_look_speed

    mesh_yaw.rotation.y = camera_root.rotation.y

    if input_camera_toggle.is_triggered():
        camera_third_person = not camera_third_person

    interpolate_camera(delta)

    if input_debug_noclip.is_triggered():
        freecam_mode = not freecam_mode
        if freecam_mode:
            # Switch to crouch collider
            collider_crouch.disabled = false
            collider_stand.disabled = true
            collision_enabled = false
            spring.remove_constraint()
            force_ground_movement = false
            desired_gravity = 0.0
            crouch_mode = false
            desired_incline_effect = 0.0
            GUIDE.enable_mapping_context(input_debug_freecam_context, false, -1)
        else:
            collision_enabled = true
            spring.add_constraint()
            force_ground_movement = true
            desired_gravity = 1.0
            linear_damp = 0.0
            GUIDE.disable_mapping_context(input_debug_freecam_context)

            if walk_mode:
                desired_incline_effect = walk_slope_effect
            else:
                desired_incline_effect = 1.0

    if input_movement_walk.is_triggered():
        walk_mode = not walk_mode
        if not freecam_mode:
            if walk_mode:
                desired_incline_effect = walk_slope_effect
            else:
                desired_incline_effect = 1.0

    if (not freecam_mode) and input_movement_jump.is_triggered():
        desired_jump_power = jump_power

    if (not freecam_mode) and input_movement_crouch.is_triggered():
        crouch_mode = not crouch_mode

    if input_debug_target_player.is_triggered():
        var crawlers: Array[CrawlerCharacter]
        crawlers.assign(get_parent().find_children('', 'CrawlerCharacter', false))
        for crawl in crawlers:
            crawl.target_position = camera_main.global_position
        debug_targeting_player = true
    elif debug_targeting_player:
        var crawlers: Array[CrawlerCharacter]
        crawlers.assign(get_parent().find_children('', 'CrawlerCharacter', false))
        for crawl in crawlers:
            crawl.target_position = Vector3.INF
        debug_targeting_player = false

    if crouch_mode:
        if collider_crouch.disabled:
            collider_crouch.disabled = false
            collider_stand.disabled = true
    elif (not freecam_mode) and collider_stand.disabled:
        # Test if we can switch to the stand collider using the shape_cast result
        # NOTE: should be an error if spring is null here
        if spring.get_spring_length() >= crouch_safe_length:
            collider_stand.disabled = false
            collider_crouch.disabled = true

    # NOTE: clear the vehicle wait flag when these inputs are released
    if vehicle_entry_wait:
        if input_action_interact.is_completed() and input_vehicle_exit.is_completed():
            vehicle_entry_wait = false
    elif vehicle != null and input_vehicle_exit.is_triggered():
        vehicle_do_exit = true

    if input_action_interact.is_triggered():
        camera_interaction_ray.interact(on_interaction)

    update_debug()

func interpolate_camera(delta: float) -> void:
    if camera_interpolation == 1.0:
        if camera_third_person:
            camera_main.position = camera_cast.target_position * camera_cast.get_closest_collision_safe_fraction()
        return

    # Recalculate interpolation based on the distance along the camera cast,
    # using the larger interpolation value.
    var third_person_offset: Vector3 = camera_cast.target_position * camera_cast.get_closest_collision_safe_fraction()
    var actual_interpolation: float
    if third_person_offset.is_zero_approx():
        actual_interpolation = 1.0
    else:
        actual_interpolation = clampf((camera_main.position / third_person_offset).length(), 0.0, 1.0)

    # Flip when going to first person
    if (not camera_third_person):
        actual_interpolation = 1.0 - actual_interpolation

    camera_interpolation = clampf(
            camera_interpolation + (delta / camera_interpolation_time),
            actual_interpolation, 1.0
    )

    if camera_third_person:
        camera_main.position = Vector3.ZERO.lerp(third_person_offset, ease(camera_interpolation, camera_interpolation_curve))
        return

    # Snap camera to zero when completing first person interpolation
    if camera_interpolation == 1.0:
        camera_main.position = Vector3.ZERO
        return

    camera_main.position = third_person_offset.lerp(Vector3.ZERO, ease(camera_interpolation, camera_interpolation_curve))

func _handle_input() -> void:
    if not is_node_ready():
        return

    if vehicle != null:
        input_vehicle()
    else:
        camera_interaction_ray.update()
        input_first_person()

    # NOTE: runs physics debug hints
    update_debug()

func input_first_person() -> void:
    var fake_shoot: bool = false
    if Engine.get_physics_frames() == 300:
        #InputManager.pause()
        #breakpoint
        #fake_shoot = true
        pass

    desired_direction = input_movement_move.value_axis_3d

    if freecam_mode:
        # From alternative freecam context
        if input_movement_jump.is_triggered():
            desired_direction += Vector3.UP
        if input_movement_crouch.is_triggered():
            desired_direction += Vector3.DOWN

    if desired_direction.length_squared() > 0.0:
        desired_speed = clampf(desired_direction.length(), 0.2, 1.0)
        desired_direction = desired_direction.normalized()

        if freecam_mode:
            desired_direction = camera_main.global_basis * desired_direction
        else:
            desired_direction = camera_root.global_basis * desired_direction

        if freecam_mode:
            linear_damp = 1.0
            desired_speed *= max_speed
            if walk_mode:
                desired_speed *= 0.5
        elif walk_mode or crouch_mode:
            desired_speed *= walk_speed
        else:
            desired_speed *= max_speed
    else:
        desired_speed = 0.0
        if freecam_mode:
            linear_damp = 10.0

    if input_movement_jump.is_completed():
        desired_jump_power = 0.0

    if (not freecam_mode) and crouch_mode:
        spring.rest_offset = -crouch_offset
    else:
        spring.rest_offset = 0.0

    if false and input_debug_target_position.is_triggered():
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

    # NOTE: this is correct to test in _handle_input(), as it will be tied to
    # physics ticks and is a continuous trigger
    if fake_shoot or input_action_shoot.is_triggered():
        if can_shoot:
            can_shoot = false
            var proj: ProjectileBody = grenade.instantiate()
            get_parent().add_child(proj)
            proj.global_position = camera_main.global_position - (0.2 * camera_main.global_basis.z)
            proj.linear_velocity = -camera_main.global_basis.z * 20
            proj.spawning_body = get_rid()
    elif not can_shoot:
        can_shoot = true

func input_vehicle() -> void:
    if (not vehicle_entry_wait) and vehicle_do_exit:
        vehicle_do_exit = false
        vehicle_entry_wait = true

        # NOTE: enable before calling exit so space queries have the right mask
        collision_enabled = true
        vehicle.exit(self)
        vehicle = null

        GUIDE.enable_mapping_context(input_movement_context)
        GUIDE.disable_mapping_context(input_vehicle_context)

        return

    if self != vehicle.driver:
        return

    vehicle.steer(input_vehicle_steer.value_axis_1d)

    # Combine acceleration and reverse inputs
    var vehicle_forward: float = input_vehicle_accelerate.value_axis_1d
    var vehicle_brake: float = input_vehicle_brake.value_axis_1d

    if input_vehicle_reverse.is_triggered():
        # Wait until neutral and slow speed to allow reversing
        if vehicle.get_gear() > 0 and vehicle.get_kph() > 1.0:
            vehicle_brake += input_vehicle_reverse.value_axis_1d
        else:
            vehicle_forward -= input_vehicle_reverse.value_axis_1d

    vehicle.forward(vehicle_forward)
    vehicle.brake(vehicle_brake)
    vehicle.handbrake(input_vehicle_handbrake.value_axis_1d)

## Called from InteractionRay.update(), handles the highest priority interaction
## found by the ray
func on_interaction(region: InteractionArea) -> void:
    print('Interacted with %s' % region.get_path())
    var object: Node3D = region.interaction_object
    if object is BaseVehicle:
        if vehicle_entry_wait:
            return

        var base_vehicle: BaseVehicle = object as BaseVehicle
        if base_vehicle.try_enter(self, region):
            vehicle = base_vehicle
            collision_enabled = false
            vehicle_entry_wait = true

            GUIDE.enable_mapping_context(input_vehicle_context)
            GUIDE.disable_mapping_context(input_movement_context)

        return

func update_debug() -> void:
    if not Engine.is_in_physics_frame():
        var want_guide_debug: bool = debug_enable and debug_guide_debugger
        var showing_guide_debug: bool = guide_debugger.visible and guide_debugger.process_mode == ProcessMode.PROCESS_MODE_ALWAYS
        if want_guide_debug != showing_guide_debug:
            if want_guide_debug:
                guide_debugger.process_mode = Node.PROCESS_MODE_ALWAYS
                guide_debugger.visible = true
            else:
                guide_debugger.process_mode = Node.PROCESS_MODE_DISABLED
                guide_debugger.visible = false

        return

    # The rest is for physics only
    vehicle_debugger.visible = debug_enable and debug_vehicle_debugger and (vehicle != null)
    if vehicle_debugger.visible and Engine.get_physics_frames() % 2 == 0:
        vehicle_debug_gear_value.text = str(vehicle.get_gear())
        vehicle_debug_speed_value.text = '%05.1f KPH' % vehicle.get_kph()
        vehicle_debug_rpm_value.text = '%04d' % vehicle.get_rpm()
