class_name PIDController extends RefCounted


var proportional: float = 1.0
var integral: float = 0.5
var derivative: float = 0.5


var _lastError: float = INF
var _errorSum: float = 0.0


func update(measure: float, target: float, delta: float) -> float:
    var error: float = target - measure

    _errorSum += error * delta

    var rate: float
    if not is_inf(_lastError):
        rate = error - _lastError
    else:
        rate = 0.0
    _lastError = error

    return (proportional * error) + (integral * _errorSum) + (derivative * rate)

func update_parameters(parameters: PhysicalControllerParameters) -> void:
    proportional = parameters.proportional
    integral = parameters.integral
    derivative = parameters.derivative
