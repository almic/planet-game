class_name CrawlerLegSetting extends Resource


@export_group('Ground Paramaters', 'ground')

## The shape to use for ground detection
@export var ground_cast_shape: Shape3D

## How far back from the ground bone to raycast
@export_range(0.05, 0.2, 0.01, 'or_greater')
var ground_hit_start: float = 0.1

## How far beyond the ground bone to raycast
@export_range(0.05, 0.2, 0.01, 'or_greater')
var ground_hit_extra: float = 0.05

## Collision mask for ground contact
@export_flags_3d_physics var ground_collision_mask: int = 1


@export_group('Step Parameters')


@export_subgroup('Step Cast', 'step_cast')

## Shape to use when searching for step target
@export var step_cast_shape: Shape3D

## How far above the rest position of the leg to start the cast. When using
## motion response for `step_cast_angle`, this could effectively be reduced by
## extreme rotations. Must be greater than `step_cast_end`.
@export_range(-1.0, 2.0, 0.01, 'or_less', 'or_greater')
var step_cast_start: float = 1.0

## How far below the rest position of the leg to end the cast. Like
## `step_cast_start`, this could effectively be raised by extreme `step_cast_angle`
## rotations. Must be less than `step_cast_start`.
@export_range(-1.0, 2.0, 0.01, 'or_less', 'or_greater')
var step_cast_end: float = -0.5

## Collision mask for step targets. This allows the step target to ignore small
## dynamic objects, searching for solid ground and effectively pushing into
## objects not considered stable ground.
@export_flags_3d_physics var step_cast_collision_mask: int = 1


@export_subgroup('Distance')

## How far between current and rest position to start moving the leg torwards the move target.
## Actual steps will be a little higher than double this value while in motion.
@export_range(0.01, 1.0, 0.01, 'or_greater')
var step_distance: float = 0.5

## If all paired legs are able to step, use this distance as a minimum for early steps.
@export_range(0.0, 0.5, 0.01, 'or_greater')
var early_step_distance: float = 0.15

## How far between current and rest position the leg should be when at rest.
## This should be very small so the legs return to a comfortable position.
@export_range(0.01, 0.5, 0.01, 'or_greater')
var rest_distance: float = 0.05


@export_subgroup('Timing')

## How long this leg must wait before it can step again
@export_range(0.01, 0.5, 0.01, 'or_greater')
var step_delay: float = 0.19

## If a paired leg has started moving in this time frame, allow this leg to
## move early to stay synchronized.
@export_range(0.0, 0.5, 0.01, 'or_greater')
var step_pair_window: float = 0.09

## How long a legs cross-pair (the set of legs that move exclusive to this leg)
## must be grounded before this leg can move.
@export_range(0.0, 0.5, 0.01, 'or_greater')
var step_crosspair_wait: float = 0.06


@export_subgroup('Motion Response')

## When in motion, the angle for the step shape cast, in the direction of motion.
## This pivots about the rest position of the leg.
@export_range(0.0, 45.0, 0.1, 'radians_as_degrees')
var step_cast_angle: float = deg_to_rad(20.0)

## When in motion, how far in the direction of travel to shift the leg move target
@export_range(0.0, 1.0, 0.01, 'or_greater')
var move_offset: float = 0.6

## When in motion, how far in the direction of travel to rotate the leg move target.
## For front and back legs, the leg only rotates forward or backward, respectively.
@export_range(0.0, 45.0, 0.1, 'radians_as_degrees')
var move_spin: float = deg_to_rad(15.0)

## How quickly to interpolate in/out of leg move offsets.
@export_range(0.01, 2.0, 0.01, 'or_greater')
var move_interp_rate: float = 1.0


@export_subgroup('Style')

## How much to lift the leg while taking a step, applies on the body's up axis
@export_range(0.0, 1.0, 0.01, 'or_greater')
var leg_lift_height: float = 0.3

## How much to swing the leg out while taking a step, 1.0 is 100% swing
@export_range(0.0, 1.0, 0.01, 'or_greater')
var leg_swing_amount: float = 0.8
