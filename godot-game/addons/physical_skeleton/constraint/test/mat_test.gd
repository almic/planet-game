## LESSONS:
##
## 1. Multiplying Matrices
##    Jolt:
##        Mat44 a, b;
##        Mat44 c = a.Multiply3x3(b);
##        c = a.Multiply3x3RightTransposed(b);
##    Godot:
##        var a: Basis
##        var b: Basis
##        var c: Basis = a * b
##        c = a * b.transposed()


@tool
extends Node

@export_tool_button('Randomize')
var btn_randomize = randomize_matrices

@export var m1: PackedVector3Array
@export var m2: PackedVector3Array


@export_tool_button('Test 3x3')
var btn_3x3 = test_mult_3x3

@export_tool_button('Test Basis')
var btn_basis = test_mult_basis

@export_tool_button('Test Transposed Splat')
var btn_trans_splat = test_mult_trans_splat

@export_tool_button('Test Trasposed Basis')
var btn_trans_basis = test_mult_trans_basis

@export_custom(PROPERTY_HINT_NONE, '', PROPERTY_USAGE_EDITOR)
var result: PackedVector3Array

func randomize_matrices() -> void:
    for mat in [m1, m2]:
        mat.clear()
        mat.resize(3)

        for c in range(3):
            var v: Vector3 = mat[c]
            for i in range(3):
                v[i] = randf_range(0.05, 1.0)
                v[i] = v[i] * v[i] * v[i]
            mat[c] = v
    notify_property_list_changed()

func test_mult_3x3() -> void:
    result.clear()
    result.resize(3)

    for i in range(3):
        result[i] = m1[0] * m2[i][0] + m1[1] * m2[i][1] + m1[2] * m2[i][2]

    notify_property_list_changed()

func test_mult_basis() -> void:
    result.clear()
    result.resize(3)

    var b1: Basis
    var b2: Basis
    for i in range(3):
        b1[i] = m1[i]
        b2[i] = m2[i]

    var br: Basis = b1 * b2
    for i in range(3):
        result[i] = br[i]

    notify_property_list_changed()

func splat(v: Vector3, axis: int) -> Vector3:
    return Vector3.ONE * v[axis]

func test_mult_trans_splat() -> void:
    result.clear()
    result.resize(3)

    result[0] = m1[0] * splat(m2[0], 0) + m1[1] * splat(m2[1], 0) + m1[2] * splat(m2[2], 0)
    result[1] = m1[0] * splat(m2[0], 1) + m1[1] * splat(m2[1], 1) + m1[2] * splat(m2[2], 1)
    result[2] = m1[0] * splat(m2[0], 2) + m1[1] * splat(m2[1], 2) + m1[2] * splat(m2[2], 2)

    notify_property_list_changed()

func test_mult_trans_basis() -> void:
    result.clear()
    result.resize(3)

    var b1: Basis
    var b2: Basis
    for i in range(3):
        b1[i] = m1[i]
        b2[i] = m2[i]

    var br: Basis = b1 * b2.transposed()
    for i in range(3):
        result[i] = br[i]

    notify_property_list_changed()
