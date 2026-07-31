## LESSONS:
##
## 1. Multiplying Quaternions
##    Jolt:
##        Quat a, b;
##        Quat c = a * b;
##    Godot:
##        var a: Quaternion
##        var b: Quaternion
##        var c: Quaternion = a * b


@tool
extends Node

@export_tool_button('Randomize')
var btn_randomize = randomize_quaternions

@export var q1: Vector4
@export var q2: Vector4


@export_tool_button('Test Jolt')
var btn_jolt = test_jolt

@export_tool_button('Test Godot')
var btn_godot = test_godot


@export_custom(PROPERTY_HINT_NONE, '', PROPERTY_USAGE_EDITOR)
var result: Vector4

func randomize_quaternions() -> void:
    for i in range(4):
        q1[i] = randf_range(-1.0, 1.0)
        q2[i] = randf_range(-1.0, 1.0)

    notify_property_list_changed()

func test_jolt() -> void:
    var x: float = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y
    var y: float = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x
    var z: float = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w
    var w: float = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z

    result = Vector4(x, y, z, w)

    notify_property_list_changed()

func test_godot() -> void:
    var quat_1: Quaternion = Quaternion(q1.x, q1.y, q1.z, q1.w)
    var quat_2: Quaternion = Quaternion(q2.x, q2.y, q2.z, q2.w)

    var q_r: Quaternion = quat_1 * quat_2
    result.x = q_r.x
    result.y = q_r.y
    result.z = q_r.z
    result.w = q_r.w

    notify_property_list_changed()
