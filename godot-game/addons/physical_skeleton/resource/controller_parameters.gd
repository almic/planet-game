class_name PhysicalControllerParameters extends Resource


const Controller = preload("uid://bdhxyktjceoqv")


## Motor response mode
@export var mode: Controller.Mode = Controller.Mode.PID:
    set(value):
        mode = value
        emit_changed()

## The proportional constant. Modify this first to get the desired speed.
@export_range(0.0, 10.0, 0.01, 'or_greater')
var proportional: float = 1.0:
    set(value):
        proportional = value
        emit_changed()

## The integral constant. Modify this to correct for accumulated errors.
@export_range(0.0, 10.0, 0.01, 'or_greater')
var integral: float = 1.0:
    set(value):
        integral = value
        emit_changed()

## The derivative constant. Modify this after proportional to reduce oscillations.
@export_range(0.0, 5.0, 0.001, 'or_greater')
var derivative: float = 0.5:
    set(value):
        derivative = value
        emit_changed()

## The derivative lowpass filter time interval, only used in IIR-LP mode
@export_range(3, 10, 1, 'prefer_slider')
var lowpass_interval: float = 3:
    set(value):
        lowpass_interval = value
        emit_changed()
