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

@export var leg_ik: IterateIK3D

var legs: Array[CrawlerLeg]


var target_position: Vector3 = Vector3.INF
var target_direction: Vector3 = Vector3.INF


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
        #desired_direction = (target_position - position).normalized()
        #desired_speed = max_speed
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

    var goal_forward: Vector3
    if target_direction.is_finite():
        goal_forward = target_direction
        # breakpoint
    else:
        goal_forward = -state.transform.basis.z

    # No yaw when this is true:
    # r <= pow(0.03125 - 0.03125 * cos_theta, 0.25)
    # NOTE: xz_dot == r
    var xz_dot: float = 1.0 - absf(state.transform.basis.tdoty(goal_forward))
    var cos_theta: float = state.transform.basis.tdotz(-goal_forward)
    var rot: float = goal_forward.signed_angle_to(-state.transform.basis.z, Vector3.DOWN)
    var yaw: float
    if xz_dot <= pow(0.03125 - 0.03125 * cos_theta, 0.25):
        goal_forward = goal_forward.rotated(Vector3.UP, rot)
        yaw = 0.0
    else:
        yaw = rot

    var pitch: float
    var pitch_axis: Vector3 = goal_forward.cross(state.transform.basis.y)
    if pitch_axis.is_zero_approx():
        pitch = (PI * 0.5) * signf(goal_forward.dot(ground_normal))
    else:
        pitch = (PI * 0.5) - goal_forward.signed_angle_to(state.transform.basis.y, pitch_axis)

    # Limit pitch
    pitch = clampf(pitch, -max_pitch, max_pitch)

    # Slide smoothly into pitch as we align the yaw
    pitch *= PI - yaw

    # Fix ground roll
    var roll: float = state.transform.basis.x.signed_angle_to(ground_normal, state.transform.basis.z)
    roll -= PI * 0.5

    var angular: Vector3 = state.transform.basis * Vector3(pitch, 0.0, roll)

    # Must fix yaw to be independent of the current pitch
    var new_forward: Vector3 = state.transform.basis.x.cross(ground_normal).normalized()
    if new_forward.is_zero_approx():
        angular += Vector3(0.0, yaw, 0.0)
    else:
        angular += Basis(state.transform.basis.x, ground_normal, new_forward) * Vector3(0.0, yaw, 0.0)

    # NOTE: technically correct, but let the body rotate without accounting for
    #       mass distribution...
    # angular = state.inverse_inertia_tensor * angular

    state.angular_velocity = state.angular_velocity.move_toward(
        angular * 4.0,
        state.step * rotation_acceleration
    )

    # NOTE: roughly 0.5 degrees per second
    if angular.is_zero_approx() and state.angular_velocity.length_squared() < 8e-5:
        state.angular_velocity = Vector3.ZERO

    # Given current angular velocity, and the difference between forward and
    # goal, apply an acceleration to the angular velocity. If the difference is
    # very small, and angular velocity is too high, then it should apply a
    # deceleration to all angular velocity.
