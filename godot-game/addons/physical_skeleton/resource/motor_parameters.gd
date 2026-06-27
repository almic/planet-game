class_name PhysicalMotorParameters extends Resource


## Velocity limit of the motor, also determines the point of friction-only motor
@export_range(0.1, 360.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var max_velocity: float = deg_to_rad(270.0)

@export_group('Torque', 'torque_')
## Rate of change for the torque, should generally be high enough to travel from
## unpowered to powered torque in fractions of a second.
@export_range(0.1, 1000.0, 0.1, 'or_less', 'or_greater', 'suffix:/s')
var torque_change_rate: float = 500.0:
    set(value):
        torque_change_rate = value
        emit_changed()

## Torque drive limit when the joint is powered
@export_range(0.0, 1000.0, 0.01, 'or_greater', 'hide_control', 'suffix:kg\u22C5m\u00B2/s\u00B2 (Nm)')
var torque_powered: float = 50.0:
    set(value):
        torque_powered = value
        emit_changed()

## Torque curve, only matters while powered and near maximum velocity. Motor
## always uses powered torque while less than half the velocity limit.
@export_exp_easing('positive_only', 'attenuation')
var torque_curve: float = 0.05:
    set(value):
        torque_curve = value
        emit_changed()

## Torque drive friction, used when a motor is unpowered or rotating too fast.
## Set to zero to make the motor frictionless.
@export_range(0.0, 50.0, 0.01, 'or_greater', 'hide_control', 'suffix:kg\u22C5m\u00B2/s\u00B2 (Nm)')
var torque_friction: float = 10.0:
    set(value):
        torque_friction = value
        emit_changed()

@export_group('Response', 'resp_')
## The proportional response constant for PID controller simulation. Modify this
## first to get the desired speed.
@export_range(0.0, 10.0, 0.01, 'or_greater')
var resp_proportional: float = 5.0

## The integral response constant for PID controller simulation. Modify this to
## correct for errors in response. This should probably not be needed as errors
## are not part of the simulation.
@export_range(0.0, 10.0, 0.01, 'or_greater')
var resp_integral: float = 0.0

## The derivative response constant for PID controller simulation. Modify this
## after proportional to reduce oscillations.
@export_range(0.0, 5.0, 0.01, 'or_greater')
var resp_derivative: float = 1.0
