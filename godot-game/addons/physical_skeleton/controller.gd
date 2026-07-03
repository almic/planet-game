extends RefCounted


enum Mode {
    ## Standard Proportional-Integral-Derivative mode
    PID,
    ## Infinite-Impulse-Response mode. Subtly changes the meaning of the PID
    ## parameters, so they may need to be adjusted
    IIR,
    ## Same as IIR, but adds a low-pass filter to the derivative term
    IIR_LP,
}


## Proportional constant
var k_p: float = 1.0
## Integral constant
var k_i: float = 0.0
## Derivative constant
var k_d: float = 0.0
## Derivative lowpass filter time interval
var k_lp: int = 3

var mode: Mode = Mode.PID:
    set(value):
        if value == mode:
            return
        mode = value
        reset_memory()

var mem: PackedFloat64Array
var mem_reset: bool = true

func _init() -> void:
    reset_memory()

func reset_memory() -> void:
    if mode == Mode.PID:
        mem.resize(2)
    elif mode == Mode.IIR:
        mem.resize(4)
    elif mode == Mode.IIR_LP:
        mem.resize(8)

    mem.fill(0.0)
    mem_reset = true

func update_parameters(parameters: PhysicalControllerParameters) -> void:
    mode = parameters.mode
    k_p = parameters.proportional
    k_i = parameters.integral
    k_d = parameters.derivative
    k_lp = parameters.lowpass_interval

## Given an input measure, target, and delta time, computes an output value
func compute(input: float, target: float, delta: float) -> float:
    if delta == 0.0:
        return 0.0

    var output: float

    if mode == Mode.PID:
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

    elif mode == Mode.IIR:
        if mem_reset:
            mem_reset = false
            mem[0] = input

        var a2: float = k_d
        var a0: float = k_p + (k_i * delta) + a2
        var a1: float = -k_p - (2.0 * a2)

        mem[3] = mem[2]
        mem[2] = mem[1]
        mem[1] = target - input
        mem[0] = mem[0] + (a0 * mem[1]) + (a1 * mem[2]) + (a2 * mem[3])
        output = mem[0]

    elif mode == Mode.IIR_LP:
        if mem_reset:
            mem_reset = false
            mem[0] = input

        var a0: float = k_p + (k_i * delta)
        var a1: float = -k_p

        mem[3] = mem[2]
        mem[2] = mem[1]
        mem[1] = target - input
        mem[0] = mem[0] + (a0 * mem[1]) + (a1 * mem[2])

        # Lowpass filter for derivative
        if k_d != 0.0:
            var a0d: float = k_d
            var a1d: float = -2.0 * a0d
            var a2d: float = a0d # why?
            var alp: float = (k_p * k_lp) / (2.0 * k_d)

            mem[5] = mem[4]
            mem[4] = (a0d * mem[1]) + (a1d * mem[2]) + (a2d * mem[3])
            mem[7] = mem[6]
            mem[6] = (alp / (alp + 1.0)) * (mem[4] + mem[5]) - ((alp - 1.0) / (alp + 1.0)) * mem[7]

        mem[0] = mem[0] + mem[6]
        output = mem[0]

    return output
