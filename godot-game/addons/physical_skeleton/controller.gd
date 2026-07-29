extends RefCounted


## Proportional constant
var k_p: float = 1.0
## Integral constant
var k_i: float = 0.0
## Derivative constant
var k_d: float = 0.0

var mem: PackedFloat64Array
var mem_cache: PackedFloat64Array
var mem_reset: bool = true
var mem_cache_reset: bool = false

func _init() -> void:
    reset_memory()

func reset_memory() -> void:
    mem.resize(3)
    mem.fill(0.0)
    mem_reset = true
    mem_cache.resize(0)

## Stores the current memory state into the cache
func store_cache() -> void:
    mem_cache.resize(0)
    mem_cache.append_array(mem)
    mem_cache_reset = mem_reset

## Loads the cache into current memory state, does nothing if memory state is
## a different size from the cache
func load_cache() -> void:
    if mem_cache.size() != mem.size():
        return

    mem.resize(0)
    mem.append_array(mem_cache)
    mem_reset = mem_cache_reset

## Applies the parameters of a resource to this controller's internal parameters
func update_parameters(parameters: PhysicalControllerParameters) -> void:
    k_p = parameters.proportional
    k_i = parameters.integral
    k_d = parameters.derivative

## Using a desired input and output, recalculates the error and updates the
## internal state. Intended for systems where the output is clamped. Must be
## called after compute() and before parameters are changed.
func set_output(output: float, delta: float) -> void:
    """
    output = (
              k_p * error
            + k_i * (old_i + (error * delta))
            + k_d * (error - prior_error)
    )

    output = (kp * error) + (ki * old_i) + (ki * error * delta) + (kd * error) - (kd * prior_error)
    output - (ki * old_i) + (kd * prior_error) = (kp * error) + (ki * error * delta) + (kd * error)
    output - (ki * old_i) + (kd * prior_error) = error * (kp + (ki * delta) + kd)
    (output - (ki * old_i) + (kd * prior_error)) / (kp + (ki * delta) + kd) = error

    error = (output - (ki * old_i) + (kd * prior_error)) / (kp + (ki * delta) + kd)

    """

    # Recover old integral and prior error
    var old_i: float = mem[0] - (mem[1] * delta)
    var prior_error: float = mem[1] - mem[2]

    # Calculate new error from desired output
    var error: float = (output - (k_i * old_i) + (k_d * prior_error)) / (k_p + (k_i * delta) + k_d)

    # Update state with new error
    var new_integral: float = old_i + (error * delta)
    var new_derivative: float = error - prior_error

    mem[0] = new_integral
    mem[1] = error
    mem[2] = new_derivative

## Given an input measure, target, and delta time, computes an output value
func compute(input: float, target: float, delta: float) -> float:
    if delta == 0.0:
        return 0.0

    var output: float

    var error: float = target - input
    var integral: float = mem[0] + (error * delta)
    var prior_error: float = mem[1]
    var derivative: float = error - prior_error
    output = (
              k_p * error
            + k_i * integral
            + k_d * derivative
    )
    mem[0] = integral
    mem[1] = error
    mem[2] = derivative

    return output
