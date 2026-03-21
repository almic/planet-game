@tool
class_name CrawlerCharacter extends CharacterController


@export_range(0.01, 8.0, 0.01, 'or_greater')
var max_speed: float = 3.0

@export_range(0.0, 30.0, 0.1, 'or_greater', 'radians_as_degrees')
var max_pitch: float = deg_to_rad(12.0)

@export_range(0.0, 360.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rotation_acceleration: float = deg_to_rad(270.0)

## Maximum rotation speed when turning
@export_range(0.1, 180.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s')
var rotation_rate: float = deg_to_rad(180.0)

@export_range(0.1, 1.0, 0.01, 'or_greater')
var rotation_overshoot: float = 0.2

@export var leg_ik: IterateIK3D

var legs: Array[CrawlerLeg]


var target_position: Vector3 = Vector3.INF
var target_direction: Vector3 = Vector3.INF

var is_stepping: bool:
    get():
        return has_desired_forward or has_desired_rotation

var has_desired_rotation: bool = false

func _ready() -> void:
    super._ready()

    # Load legs from children
    legs.assign(find_children('', 'CrawlerLeg'))

    var index: int = 0
    for leg in legs:
        leg.body = self
        leg.index = index

        index += 1

        # Copy collision mask to casters
        leg.shape_cast.collision_mask = collision_mask

    leg_ik.active = not Engine.is_editor_hint()
    # leg_ik.active = false

func _handle_input() -> void:

    if target_position.is_finite() and (target_position - position).length_squared() > 4.0:
        target_direction = (target_position - position).normalized()
        desired_direction = (target_position - position).normalized()
        desired_speed = max_speed
    elif not desired_direction.is_zero_approx():
        desired_direction = Vector3.ZERO
        desired_speed = 0.0
        target_position = Vector3.INF


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    _update_legs(state)

    _solve_rotation(state)

    super._integrate_forces(state)

func _update_legs(state: PhysicsDirectBodyState3D) -> void:

    for leg in legs:
        leg.update(state)


func _calculate_ground_force(state: PhysicsDirectBodyState3D) -> void:

    desired_acceleration = -state.total_gravity

    ground_normal = Vector3.UP
    ground_rel_con_velocity = state.linear_velocity
    ground_velocity = ground_rel_con_velocity.slide(ground_normal)
    ground_friction = Vector3.ZERO

    if not ground_velocity.is_zero_approx():
        ground_direction = ground_velocity.normalized()
    else:
        ground_direction = Vector3.ZERO

    # TODO: I don't like how this uses desired_acceleration... either make this
    #       write to ground_friction, or make desired_acceleration BETTER (???)
    if has_desired_forward and (not ground_direction.is_zero_approx()):
        # If any legs are not moving and uncomfortable, slow down
        for leg in legs:
            if (not leg.is_moving) and (not leg.is_comfortable):
                var stopping: Vector3 = -ground_direction * deceleration
                var decel_limit: float = ground_velocity.dot(ground_direction) / state.step
                stopping = stopping.limit_length(decel_limit)
                desired_acceleration += stopping
                break

    is_on_floor = true

func _solve_rotation(state: PhysicsDirectBodyState3D) -> void:

    var grounded_legs: int = 0
    var can_do_yaw: bool = true
    for leg in legs:
        if leg.is_grounded:
            grounded_legs += 1
        if can_do_yaw and (not leg.is_comfortable) and (not leg.is_moving):
            can_do_yaw = false

    has_desired_rotation = false

    # Must have at least 1 leg grounded to perform rotation
    if grounded_legs == 0:
        # TODO: damp rotation as if by air friction
        return

    var leg_count: int = legs.size()
    var grounded_leg_factor: float = float(grounded_legs) / float(leg_count)

    var preferred_forward: Vector3
    var preferred_right: Vector3

    var main_legs: Array[CrawlerLeg] = [
        legs[0], legs[1],
        legs[leg_count - 2], legs[leg_count - 1]
    ]
    var ground_points: PackedVector3Array
    ground_points.resize(4)

    var using_rest_point: bool = false
    var using_ground_points: bool = true
    for i in range(4):
        var leg: CrawlerLeg = main_legs[i]
        if leg.is_grounded:
            ground_points[i] = leg.target.position
        elif leg.is_moving:
            ground_points[i] = leg.step_target
        elif using_rest_point:
            # Cannot use more than 1 rest point, use current orientation
            preferred_forward = -state.transform.basis.z
            preferred_right = state.transform.basis.x
            using_ground_points = false
            break
        else:
            using_rest_point = true
            ground_points[i] = leg.target_global_rest

    if using_ground_points:
        preferred_forward = (
                  (ground_points[0] - ground_points[2])
                + (ground_points[1] - ground_points[3])
        ).normalized()
        preferred_right = (
                  (ground_points[1] - ground_points[0])
                + (ground_points[3] - ground_points[2])
        ).normalized()

    var preferred_up: Vector3 = preferred_right.cross(preferred_forward).normalized()
    # var preferred_basis: Basis = Basis(preferred_right, preferred_up, preferred_forward)
    # print(preferred_basis)

    var current_forward: Vector3 = -state.transform.basis.z
    var current_right: Vector3 = state.transform.basis.x

    var yaw: float
    if can_do_yaw:
        # Only yaw when this is true:
        # r > pow(0.03125 - 0.03125 * cos_theta, 0.25)
        # NOTE: xz_dot == r
        var xz_dot: float = 1.0 - absf(preferred_up.dot(target_direction))
        var cos_theta: float = preferred_forward.dot(target_direction)
        if xz_dot > pow(0.03125 - 0.03125 * cos_theta, 0.25):
            yaw = current_forward.signed_angle_2(target_direction, preferred_up)
            # NOTE: about 0.5 degrees
            if absf(yaw) > 8.7e-3:
                has_desired_rotation = true

    var roll: float = current_right.signed_angle_2(preferred_right, -preferred_forward)
    var pitch: float = current_forward.signed_angle_2(preferred_forward, preferred_right)

    var angular: Vector3 = Vector3(pitch, yaw, roll)

    var max_angular: Vector3 = angular / state.step
    var limited_angular: Vector3 = angular.sign() * max_angular.abs().minf(rotation_rate * (1.0 / rotation_overshoot))
    var target_angular: Vector3 = state.transform.basis * limited_angular

    state.angular_velocity = state.angular_velocity.move_toward(
            target_angular * rotation_overshoot,
            state.step * rotation_acceleration * grounded_leg_factor
    )

    # NOTE: roughly 0.5 degrees per second
    if target_angular.is_zero_approx() and state.angular_velocity.length_squared() < 8e-5:
        state.angular_velocity = Vector3.ZERO
