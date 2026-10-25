class_name BaseVehicle extends Vehicle


@export var exit_position: Marker3D
@export var camera_target: Marker3D


@export_group('Seats')

@export var driver_entry: InteractionArea
@export var passenger_entry: Array[InteractionArea]


@export_group('Controls')

@export_subgroup('Steering', 'steer')

## Make steering inputs turn a virtual wheel, instead of instantly applying a
## turning value directly.
@export var steer_enable_virtual: bool = false

## Rate of forward input acceleration when driving
@export_range(0.1, 50.0, 0.1)
var steer_acceleration: float = 25

## Limit of the forward input acceleration
@export_range(0.1, 20.0, 0.1)
var steer_acceleration_limit: float = 10.0

## Steering curve, lower values approach input quicker. For instance, steering
## right at 1.0 for 0.2 seconds will result in a final steer of ~0.544 with a
## curve of 1. The constant rate of change is `(right * e) / curve`.
@export_range(0.01, 2.0, 0.01, 'or_greater')
var steer_wheel_curve: float = 1.0

## Makes steering more realistic by having steered wheels apply turning back to
## the virtual steering wheel.
@export var steer_enable_integrated: bool = false

## How much feedback to apply to the virtual wheel from the wheels.
@export_range(0.01, 1.2, 0.01, 'or_greater')
var steer_integrated_feedback: float = 1.2


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


@export_group("Debug", "dbg")

@export_custom(PROPERTY_HINT_GROUP_ENABLE, 'checkbox_only')
var dbg_enable: bool = false

## When accelerating while stationary (sleeping), start a timer which ends once
## the vehicle exceeds 60mph and print the timer
@export var dbg_print_zero_sixty: bool = false

@export var dbg_show_wheel_slip: bool = false

@export var dbg_print_gear_changes: bool = false


## Current driver of this vehicle
var driver: Node3D = null

## Current passengers of this vehicle
var passengers: Array[Node3D] = []

## Multiplier to gravity acceleration
var desired_gravity: float = 1.0


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
## Current right input
var _virtual_right: float = 0.0
## Current right input speed
var _virtual_right_speed: float = 0.0

var _flip_timer: float = 0.0
var _do_flip: bool = false


func _ready() -> void:
    if dbg_enable and dbg_show_wheel_slip:
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
    var controller: WheeledVehicleController = get_controller() as WheeledVehicleController
    if not controller:
        return 0
    return controller.get_current_gear()

func get_kmh() -> float:
    var controller: WheeledVehicleController = get_controller() as WheeledVehicleController
    if not controller:
        return 0
    return controller.get_speed_kmh()

func get_mph() -> float:
    var controller: WheeledVehicleController = get_controller() as WheeledVehicleController
    if not controller:
        return 0
    return controller.get_speed_mph()

func _reset() -> void:
    _forward = 0
    _right = 0
    _brake = 0
    _handbrake = 0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    var delta: float = state.step

    # Apply damping forces immediately
    if not is_zero_approx(state.total_linear_damp):
        state.linear_velocity -= state.linear_velocity * state.total_linear_damp * state.step
    if not is_zero_approx(state.total_angular_damp):
        state.angular_velocity -= state.angular_velocity * state.total_angular_damp * state.step

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

    var controller: WheeledVehicleController = get_controller() as WheeledVehicleController
    if not controller:
        _reset()
        return

    update_debug(delta)

    if steer_enable_virtual:
        if steer_enable_integrated:
            integrate_steering(state)
            # update_right_two(state)

        update_virtual_steer(delta)

        # Smooth out the change in steering
        const E = exp(1)
        var current_right: float = controller.get_right_input()
        var offset: float = minf(1.0, (absf(_virtual_right - current_right) * E * delta) / steer_wheel_curve)

        _right = move_toward(current_right, _virtual_right, offset)
    else:
        if _virtual_right != 0.0:
            _virtual_right = 0.0
        if _virtual_right_speed != 0.0:
            _virtual_right_speed = 0.0

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
                    dbg_enable
                and dbg_print_zero_sixty
                and sleeping
                and _forward > 0.0
                and _zero_sixty_timer == -1.0
        ):
            _zero_sixty_timer = 0.0
        # Wake up when input is received
        sleeping = false

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

func integrate_steering(state: PhysicsDirectBodyState3D) -> void:
    # TODO: Do a better job of calculating the steering angle change, as the
    # steer input is -1.0 - 1.0, but the steer angle and vehicle turn are in radians
    var vehicle_turn: float = -state.transform.basis.tdoty(state.angular_velocity)
    var controller: WheeledVehicleController = get_controller() as WheeledVehicleController

    var avg_steer: float = 0.0
    var steer_count: int = 0
    var i: int = -1
    for w in controller.get_wheel_info():
        i += 1
        if not w.has_contact:
            continue
        var w_setting: WheelSettings = settings.wheels[i] as WheelSettings
        if w_setting.max_steer_angle == 0.0:
            continue
        avg_steer += w.steer_angle
        steer_count += 1

    if steer_count < 1:
        return

    avg_steer /= steer_count
    if abs(avg_steer) < 1e-6:
        return

    if signf(vehicle_turn) == signf(avg_steer):
        avg_steer = -avg_steer

    vehicle_turn = abs(vehicle_turn) * state.step

    _virtual_right = clampf(
        _virtual_right + (
            clampf(
                (vehicle_turn / avg_steer) * steer_integrated_feedback,
                -vehicle_turn, vehicle_turn
            )
        ),
        -1.0, 1.0
    )

func update_virtual_steer(delta: float) -> void:
    const DECAY_RATE: float = 0.33

    # NOTE: slowly decay input speed, do not reset to zero
    if _right == 0.0 and _virtual_right_speed != 0.0:
        _virtual_right_speed = move_toward(
                _virtual_right_speed,
                0.0,
                steer_acceleration * delta * DECAY_RATE
        )

    if _virtual_right == _right:
        return

    var sign_right: float = signf(_right)

    # Reset acceleration when changing direction
    if _right != 0.0 and signf(_virtual_right_speed) != sign_right:
        _virtual_right_speed = 0.0

    _virtual_right_speed = move_toward(
            _virtual_right_speed,
            sign_right * steer_acceleration_limit,
            steer_acceleration * delta
    )

    _virtual_right = move_toward(_virtual_right, _right, absf(_virtual_right_speed) * delta)

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

func update_debug(delta: float) -> void:
    if not dbg_enable:
        return

    var controller: WheeledVehicleController = get_controller() as WheeledVehicleController

    if dbg_show_wheel_slip:
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

    if dbg_print_zero_sixty:
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

    if dbg_print_gear_changes:
        var gear: int = controller.get_current_gear()
        if _last_gear != gear:
            # GlobalWorld.print('Gear: %d -> %d' % [_last_gear, gear])
            print('Gear: %d -> %d' % [_last_gear, gear])
            _last_gear = gear
