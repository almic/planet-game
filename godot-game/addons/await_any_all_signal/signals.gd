@tool
extends Node

const NAME: StringName = &'name'
const RESULT_LIST: StringName = &'result_list'
const CALL_LIST: StringName = &'call_list'
const WAIT_LIST: StringName = &'wait_list'

## Returns the index of the first signal that emits, and populates the result
## array with the values passed to the emitting signal
func any(signal_list: Array[Signal], result: Array[Variant] = []) -> Signal:
    var count: int = signal_list.size()
    var obj := Object.new()
    obj.set_meta(NAME, 'signal_func_await_any')
    obj.add_user_signal(NAME)
    var any_signal := Signal(obj, NAME)

    if count == 0:
        any_signal.emit.call_deferred(-1)
        obj.free.call_deferred()
        return any_signal

    var on_result = func (...args: Array):
        var signal_index: int = args.back()
        result.assign(args.slice(0, args.size() - 1))
        var inner_call_list: Array = obj.get_meta(CALL_LIST)
        for index in range(count):
            signal_list[index].disconnect(inner_call_list[index])
        any_signal.emit(signal_index)
        obj.free()

    obj.set_meta(CALL_LIST, Array())
    var outer_call_list: Array = obj.get_meta(CALL_LIST)
    outer_call_list.resize(count)

    for index in range(count):
        outer_call_list[index] = on_result.bind(index)
        signal_list[index].connect(outer_call_list[index])

    return any_signal

func all(signal_list: Array[Signal]) -> Signal:
    var count: int = signal_list.size()
    var obj := Object.new()
    obj.set_meta(NAME, 'signal_func_await_all')
    obj.add_user_signal(NAME)
    var all_signal := Signal(obj, NAME)

    if count == 0:
        all_signal.emit.call_deferred([])
        obj.free.call_deferred()
        return all_signal

    var on_result = func (...args: Array):
        var signal_index: int = args.back()
        var inner_wait_list: PackedByteArray = obj.get_meta(WAIT_LIST)
        inner_wait_list[signal_index] = 0
        var inner_result: Array = obj.get_meta(RESULT_LIST)
        inner_result[signal_index] = args.slice(0, args.size() - 1)
        if not inner_wait_list.has(1):
            all_signal.emit(inner_result)
            obj.free()

    obj.set_meta(RESULT_LIST, Array())
    var outer_result: Array = obj.get_meta(RESULT_LIST)
    outer_result.resize(count)

    # An integer counter may also be viable, but this is more robust
    obj.set_meta(WAIT_LIST, PackedByteArray())
    var outer_wait_list: PackedByteArray = obj.get_meta(WAIT_LIST)
    outer_wait_list.resize(count)
    outer_wait_list.fill(1)

    for index in range(count):
        signal_list[index].connect(on_result.bind(index), CONNECT_ONE_SHOT)

    return all_signal
