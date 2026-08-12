class_name PhysicalMotorParameters extends Resource


## Velocity limit of the motor, which it will not try to exceed in normal
## operation.
@export_range(0.1, 360.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var max_velocity: float = deg_to_rad(270.0)

## Acceleration limit of the motor
@export_range(0.1, 1440.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s\u00B2')
var max_acceleration: float = deg_to_rad(720.0)

## Motor velocity damping. Each physics tick the angular velocity between the two
## bodies on the motor axis is reduced by (joint_velocity * damping * delta)
## according to their relative mass.
@export_range(0.0, 1.0, 0.001)
var damping: float = 0.08


@export_group('Torque Curve', 'torque_')

## Torque drive limit when the joint is powered
@export_range(0.0, 1000.0, 0.01, 'or_greater', 'hide_control', 'suffix:kg\u22C5m\u00B2/s\u00B2 (Nm)')
var torque_powered_max: float = 50.0:
    set(value):
        torque_powered_max = value
        emit_changed()

## Torque zero speed relative to max velocity. This defines the velocity where
## the motor torque becomes zero and is only affected by external forces.
@export_range(0.0, 1.0, 0.01, 'or_greater', 'suffix:+ 1.0')
var torque_zero_speed: float = 0.2:
    set(value):
        torque_zero_speed = value
        emit_changed()

## Torque curve,
@export_exp_easing('positive_only', 'attenuation')
var torque_curve: float = 0.2:
    set(value):
        torque_curve = value
        emit_changed()


@export_group('Controller')
## Controller parameters for target angle
@export var angle_controller: PhysicalControllerParameters:
    set(value):
        _disconnect_changed(angle_controller)
        angle_controller = value
        _connect_changed(angle_controller)

## Controller parameters for motor velocity
@export var motor_controller: PhysicalControllerParameters:
    set(value):
        _disconnect_changed(motor_controller)
        motor_controller = value
        _connect_changed(motor_controller)


func _connect_changed(res: Resource) -> void:
    if res and (not res.changed.is_connected(emit_changed)):
        res.changed.connect(emit_changed)

func _disconnect_changed(res: Resource) -> void:
    if res and res.changed.is_connected(emit_changed):
        res.changed.disconnect(emit_changed)
