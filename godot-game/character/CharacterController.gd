class_name CharacterController extends RigidBody3D

@export var shape_cast: ShapeCast3D

@export var height_offset: float = 0.0
@export var stand_strength: float = 100.0
@export var stand_damping: float = 50.0

@export var speed: float = 1000


var is_on_floor: bool = false


func _physics_process(delta: float) -> void:
    if is_on_floor:
        var moving: bool = false
        if Input.is_action_pressed(&'ui_up'):
            moving = true
            apply_central_force(-global_basis.z * speed)
        if Input.is_action_pressed(&'ui_down'):
            moving = true
            apply_central_force(global_basis.z * speed)
        if Input.is_action_pressed(&'ui_left'):
            moving = true
            apply_central_force(-global_basis.x * speed)
        if Input.is_action_pressed(&'ui_right'):
            moving = true
            apply_central_force(global_basis.x * speed)
        if not moving and not linear_velocity.is_zero_approx():
            linear_velocity -= linear_velocity * 0.1


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:

    if not shape_cast.is_colliding():
        if is_on_floor:
            is_on_floor = false
        return

    if not is_on_floor:
        is_on_floor = true

    var ground: Vector3 = shape_cast.get_collision_point(0)
    var height: float = state.transform.origin.y - ground.y
    var up_velocity: float = state.linear_velocity.dot(state.transform.basis.y)

    var offset: float = height_offset - height
    var spring: float = (offset * stand_strength * mass) - (up_velocity * stand_damping * mass)

    state.apply_central_force(state.transform.basis.y * spring)
