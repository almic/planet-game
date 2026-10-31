class_name BaseVehicle extends Vehicle


const TO_MILES: float = 1.0 / 1.609344




@export_group('Seats')

@export var exit_position: Marker3D
@export var driver_entry: InteractionArea
@export var passenger_entry: Array[InteractionArea]


@export_group('Camera', 'camera')

## Target point of the camera for third-person passengers
@export var camera_target: Marker3D

## How far to push the camera back
@export_range(0.01, 10.0, 0.01, 'or_greater')
var camera_distance: float = 5.0


@export_group('Air Friction', 'air_friction')

## The XYZ drag coefficients when direction of motion is aligned with the body's
## local positive axes.
@export var air_friction_coef_plus: Vector3 = Vector3.ONE
## The XYZ drag coefficients when direction of motion is aligned with the body's
## local negative axes.
@export var air_friction_coef_minus: Vector3 = Vector3.ONE
## The surface area of the body when viewed from the local XYZ axes
@export var air_friction_surface_area: Vector3 = Vector3.ONE


@export_group('Controls')

@export_subgroup('Forward', 'forward')

## If forward input acceleration is applied. This can smooth out sliding when
## accelerating from stand-still on a keyboard.
@export var forward_enable_virtual: bool = false

## Rate of forward input acceleration when driving
@export_range(0.01, 2.0, 0.01)
var forward_acceleration: float = 0.5

## Limit of the forward input acceleration
@export_range(0.01, 2.0, 0.01)
var forward_acceleration_limit: float = 1.0

## Constant forward input reset speed when not applying input, or target input
## opposes the current input
@export_range(0.01, 2.0, 0.01)
var forward_reset_speed: float = 2.0

## In MPH, the remapping range maximum for forward input. Suited for keyboards
## to prevent inputs too high for a given vehicle speed. Set to zero to disable.
@export_range(0, 80, 1, 'or_greater', 'suffix:mph')
var forward_input_speed_max: int = 80

## How many ticks of slip before interrupting forward input. Suited for keyboards
## to prevent constant slip during acceleration. Set to zero to disable.
@export_range(0, 10, 1, 'or_greater')
var forward_input_slip_rate: int = 5

@export var forward_input_curve: Curve


@export_group('Stats', 'stat')

## When positive, enables speed history tracking for KPH and MPH. Set to zero
## to disable.
@export_range(0, 10, 1, 'or_greater')
var stat_speed_history: int = 5


@export_group('Debug', 'debug')

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var debug_enable: bool = false

@export var debug_steering_axes: bool = false
var _debug_steering_axes_ids: PackedInt32Array

## When accelerating while stationary (sleeping), start a timer which ends once
## the vehicle exceeds 60mph and print the timer
@export var debug_print_zero_sixty: bool = false

@export var debug_show_wheel_slip: bool = false

@export var debug_print_gear_changes: bool = false


## Current driver of this vehicle
var driver: Node3D = null

## Current passengers of this vehicle
var passengers: Array[Node3D] = []

## Multiplier to gravity acceleration
var desired_gravity: float = 1.0

## Current controller, this is updated each physics tick
var controller: WheeledVehicleController = null


var _forward: float = 0
var _right: float = 0
var _brake: float = 0
var _handbrake: float = 0

var _zero_sixty_timer: float = -1.0

var _last_gear: int = 0

## Current forward input
var _virtual_forward: float = 0.0
## Current forward input speed
var _virtual_forward_speed: float = 0.0
## Ticks of slip during acceleration
var _vehicle_forward_slip_ticks: int = 0

var _flip_timer: float = 0.0
var _do_flip: bool = false

var _speed_history: PackedFloat32Array
var _speed_history_index: int = -1


func _ready() -> void:
    if debug_enable and debug_show_wheel_slip:
        # Make all wheel materials unique copies
        for w in wheel_nodes:
            var mesh_instance: MeshInstance3D = w as MeshInstance3D
            if not mesh_instance:
                continue
            var mesh: PrimitiveMesh = mesh_instance.mesh as PrimitiveMesh
            if not mesh:
                continue
            mesh = mesh.duplicate()
            mesh.material = mesh.material.duplicate()
            mesh_instance.mesh = mesh

## Attempts to put the given node into this vehicle using an interaction area
## as the entry point. Returns true if the node was made a driver or passenger.
func try_enter(node: Node3D, seat: InteractionArea) -> bool:
    if node == null:
        push_error('Vehicle.try_enter() called with a null node! Vehicle at %s' % get_path())
        return false

    if seat == driver_entry:
        if driver != null:
            return false
        driver = node
        return true

    if seat in passenger_entry:
        if passengers.size() < passenger_entry.size():
            passengers.append(node)
            return true
        return false

    var seat_path: NodePath
    if seat.is_inside_tree():
        seat_path = seat.get_path()

    push_error(
        (
            'Vehicle.try_enter() called with unknown seat! Vehicle at %s with requested seat %s'
        ) % [ get_path(), seat_path ]
    )

    return false

## Removes the node as a driver or passenger, returns true if they were.
func exit(node: Node3D) -> bool:
    if node == null:
        push_error('Vehicle.exit() called with a null node! Vehicle at %s' % get_path())
        return false

    if node == driver:
        driver = null
        return true

    if node in passengers:
        passengers.erase(node)
        return true

    return false

func forward(value: float) -> void:
    _forward = clampf(value, -1.0, 1.0)

func steer(right: float) -> void:
    _right = clampf(right, -1.0, 1.0)

func brake(amount: float) -> void:
    _brake = clampf(amount, 0.0, 1.0)

func handbrake(amount: float) -> void:
    _handbrake = clampf(amount, 0.0, 1.0)

func get_exit_position() -> Vector3:
    return exit_position.global_position + settings.up

func get_gear() -> int:
    if not controller:
        return 0
    return controller.get_current_gear()

func get_kph() -> float:
    if stat_speed_history == 0:
        return get_current_kph()

    return _speed_history.average()

func get_mph() -> float:
    return get_kph() * TO_MILES

func get_current_kph() -> float:
    if stat_speed_history > 0 and _speed_history_index >= 0:
        return _speed_history[posmod(_speed_history_index - 1, stat_speed_history)]

    if not controller:
        return 0
    return controller.get_speed_kmh()

func get_current_mph() -> float:
    return get_current_kph() * TO_MILES

func get_rpm() -> float:
    if not controller:
        return 0
    return controller.get_current_rpm()

func _reset() -> void:
    _forward = 0
    _right = 0
    _brake = 0
    _handbrake = 0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    controller = get_controller() as WheeledVehicleController

    var delta: float = state.step

    # Apply damping forces immediately
    if not is_zero_approx(state.total_linear_damp):
        state.linear_velocity -= state.linear_velocity * state.total_linear_damp * state.step
    if not is_zero_approx(state.total_angular_damp):
        state.angular_velocity -= state.angular_velocity * state.total_angular_damp * state.step

    # "Air drag"
    # (1/2) * Density * v^2 * Area * Coefficient
    var air_friction: Vector3 = Vector3.ZERO
    var linear_speed: float = state.linear_velocity.length()

    if not is_zero_approx(linear_speed):
        var linear_direction: Vector3 = state.linear_velocity.normalized()
        var alignment: Vector3 = Vector3(
                state.transform.basis.tdotx(linear_direction),
                state.transform.basis.tdoty(linear_direction),
                state.transform.basis.tdotz(linear_direction)
        )

        var surface_area: float = (
                  air_friction_surface_area.x * absf(alignment.x)
                + air_friction_surface_area.y * absf(alignment.y)
                + air_friction_surface_area.z * absf(alignment.z)
        )

        var blends: Vector3 = (alignment + Vector3.ONE) * 0.5
        blends = air_friction_coef_minus * (Vector3.ONE - blends) + (air_friction_coef_plus * blends)
        var drag_coef: float = (
                  blends.x * absf(alignment.x)
                + blends.y * absf(alignment.y)
                + blends.z * absf(alignment.z)
        )

        air_friction = (
                0.5 * 1.21 # Fluid density
                * -linear_direction * linear_speed * linear_speed
                * surface_area
                * drag_coef
        ) * state.inverse_mass # NOTE: Proportional to mass!!!

    state.linear_velocity += air_friction * state.step

    # Gravity
    state.linear_velocity += state.total_gravity * desired_gravity * state.step

    if _flip_timer > 0.0:
        _flip_timer = maxf(_flip_timer - delta, 0.0)

    if _do_flip:
        state.apply_central_impulse(Vector3.UP * 5.0 * mass)
        # TODO: figure out if on left or right of the truck. I'm too dumb.
        var side_dir: float = signf(global_basis.x.y)
        if absf(global_basis.x.y) < 0.1:
            side_dir = 2.0
        state.apply_torque_impulse(global_basis.z * -side_dir * inertia.z * 1.2)
        _do_flip = false

    if not controller:
        if stat_speed_history > 0 and _speed_history_index >= 0:
            # Clear speed when losing controller
            _speed_history.fill(0)
            _speed_history_index = -1
        _reset()
        return

    if stat_speed_history > 0:
        if _speed_history_index == -1:
            _speed_history.resize(stat_speed_history)
            _speed_history.fill(controller.get_speed_kmh())
            _speed_history_index = 1 % stat_speed_history
        elif _speed_history.size() != stat_speed_history:
            var avg: float = _speed_history.average()
            _speed_history.resize(stat_speed_history)
            _speed_history.fill(avg)
            _speed_history[0] = controller.get_speed_kmh()
            _speed_history_index = 1 % stat_speed_history
        else:
            _speed_history[_speed_history_index] = controller.get_speed_kmh()
            _speed_history_index = (_speed_history_index + 1) % stat_speed_history

    update_debug(delta, state.transform)

    if forward_enable_virtual:
        update_virtual_forward(delta)
        _forward = _virtual_forward
    else:
        if _virtual_forward != 0.0:
            _virtual_forward = 0.0
        if _virtual_forward_speed != 0.0:
            _virtual_forward_speed = 0.0

    if (
                forward_input_slip_rate > 0
            and (not sleeping)
            and controller.is_any_driven_wheel_slipping()
    ):
        _vehicle_forward_slip_ticks += 1
        if _vehicle_forward_slip_ticks >= forward_input_slip_rate:
            _vehicle_forward_slip_ticks = 0
            _forward = 0

    if _forward > 0 and forward_input_speed_max > 0:
        _forward = remap(
                _forward,
                0.0, 1.0,
                0.0, minf(1.0, (get_mph() + 1.0) / forward_input_speed_max)
        )
        _forward = forward_input_curve.sample_baked(_forward)

    if not (
            is_zero_approx(_forward)
        and is_zero_approx(_right)
        and is_zero_approx(_brake)
        and is_zero_approx(_handbrake)
    ):
        if (
                    debug_enable
                and debug_print_zero_sixty
                and sleeping
                and _forward > 0.0
                and _zero_sixty_timer == -1.0
        ):
            _zero_sixty_timer = 0.0
        # Wake up when input is received
        sleeping = false

    # Handle abrupt angle changes when changing keyboard steer
    var reset_keyboard: bool = (
            InputManager.is_keyboard()
        and (not is_equal_approx(controller.get_right_input(), _right))
    )
    var reset_controller: bool = (
            (not InputManager.is_keyboard())
        and absf(controller.virtual_steer - _right) < 1e-6
    )
    if (
            controller.virtual_steer_enabled
            and (reset_keyboard or reset_controller)
    ):
        controller.virtual_steer_velocity = 0.0

    controller.set_driver_input(
            _forward,
            _right,
            _brake,
            _handbrake
    )

    #if not is_zero_approx(_forward) and controller.is_any_driven_wheel_slipping():
        #print('slipping!')
    #if not is_zero_approx(input_forward):
        #print(controller.get_current_gear())
        #print(controller.get_current_rpm())

    _reset()

func update_virtual_forward(delta: float) -> void:
    # Rate of input acceleration decay
    const DECAY_RATE: float = 0.33

    if _forward == 0.0:
        if _virtual_forward_speed != 0.0:
            # NOTE: slowly decay input speed, do not reset to zero
            _virtual_forward_speed = move_toward(
                    _virtual_forward_speed,
                    0.0,
                    forward_acceleration * delta * DECAY_RATE
            )

        if _virtual_forward != 0.0:
            # NOTE: release accelerator when no input
            _virtual_forward = move_toward(
                    _virtual_forward,
                    0.0,
                    forward_reset_speed * delta
            )

    if _virtual_forward == _forward:
        return

    var sign_forward: float = signf(_forward)

    # Reset acceleration when changing direction
    if _forward != 0.0 and signf(_virtual_forward_speed) != sign_forward:
        _virtual_forward_speed = 0.0

    var total_delta: float = 0.0
    if _virtual_forward != 0.0 and signf(_virtual_forward) != sign_forward:
        # Travel to zero using the reset speed
        var new_virtual_forward: float = move_toward(
                _virtual_forward,
                0.0,
                forward_reset_speed * delta
        )
        total_delta = _virtual_forward - new_virtual_forward
        _virtual_forward = new_virtual_forward

        if _virtual_forward != 0.0:
            return

    _virtual_forward_speed = move_toward(
            _virtual_forward_speed,
            sign_forward * forward_acceleration_limit,
            forward_acceleration * delta
    )

    _virtual_forward = move_toward(
            _virtual_forward,
            _forward,
            maxf(0.0, (absf(_virtual_forward_speed) * delta) - total_delta)
    )

func flip(from: Vector3) -> void:
    if _flip_timer != 0.0:
        return

    _do_flip = true
    _flip_timer = 1.0

func update_debug(delta: float, xform: Transform3D) -> void:
    if not debug_enable:
        return

    if debug_steering_axes:
        for i in range(settings.wheels.size()):
            if i >= _debug_steering_axes_ids.size():
                _debug_steering_axes_ids.append(0)

            var wheel_settings := settings.wheels[i]
            var steer_axis_pos: Vector3 = wheel_settings.position + controller.get_suspension_length(i) * wheel_settings.get_suspension_direction()
            _debug_steering_axes_ids[i] = DebugDraw.vector(
                xform * steer_axis_pos,
                xform.basis * wheel_settings.get_steering_axis(),
                Color.DARK_GOLDENROD,
                _debug_steering_axes_ids[i],
                0.1
            )

    if debug_show_wheel_slip:
        var wheel_infos: Array[Dictionary] = controller.get_wheel_info()
        var i: int = 0
        for wheel in wheel_nodes:
            if wheel is MeshInstance3D:
                var info: Dictionary = wheel_infos[i]
                var mat: StandardMaterial3D = wheel.mesh.surface_get_material(0) as StandardMaterial3D
                if not info['has_contact']:
                    mat.albedo_color = Color(0.0, 0.0, 1.0)
                elif info['slip_long'] > 0.1:
                    mat.albedo_color = Color(1.0, 0.0, 0.0)
                else:
                    mat.albedo_color = Color(remap(info['slip_long'], 0.0, 0.1, 0.0, 1.0), 1.0, 0.0)
            i += 1

    if debug_print_zero_sixty:
        var mph: float = linear_velocity.length() * 3.6 / 1.609344
        if _zero_sixty_timer != -1.0:
            _zero_sixty_timer += delta
            if _forward < 0.0 or _brake > 0.0:
                # GlobalWorld.print("0-%.1f: %.3fs" % [mph, _zero_sixty_timer])
                print("0-%.1f: %.3fs" % [mph, _zero_sixty_timer])
                _zero_sixty_timer = -1.0
            elif mph >= 60.0:
                # GlobalWorld.print("0-60: %.3fs" % _zero_sixty_timer)
                print("0-60: %.3fs" % _zero_sixty_timer)
                _zero_sixty_timer = -1.0

    if debug_print_gear_changes:
        var gear: int = controller.get_current_gear()
        if _last_gear != gear:
            # GlobalWorld.print('Gear: %d -> %d' % [_last_gear, gear])
            print('Gear: %d -> %d' % [_last_gear, gear])
            _last_gear = gear
