Moves using four/ six legs, can walk along walls and ceilings. Small size and generally easy to destroy.

# Previous Work
- https://youtu.be/G_seJ2Yg1GA
  Spider bot created in Godot
- https://youtu.be/0MHY2TDeMLM
  Reactive bone simulation
- https://www.youtube.com/playlist?list=PLjEdfKCj3OU9pxjhuIgpWZ6Fpq-8WNWUl
  More generalized walking creature in Minecraft using Kotlin
- https://youtu.be/MbaPDWfbNLo
  Demonstration of IK and blending with animations
- https://youtu.be/L9IVlx2n_ag
  Setup for third-person shooter with animations and IK. Source available to look at.
- https://youtu.be/LNidsMesxSE
  Overgrowth dev talk on procedural animation
- https://youtu.be/NfN1oRZPGZ8
  Reference for ant (hexapod) leg motion. Seems to generalize to this statement: "For the leg that decides to move, also move the legs diagonal to the adjacent legs." Three legs should be firmly planted, and the other three move, as if a tripod shape is made.

# Big One
The larger crawler will have 6 legs and a long body. It is probably armored. Should appear in two scales: a bit over one meter in standing height, and about 50-60 cm.

# Little One
The smaller crawler will have 4 legs with a round body. Not armored, very fragile. Between 25-30 cm in height.

# Need
- General leg support/ walking system. Handles missing legs and walking with an arbitrary number of leg pairs. No global orientations, can handle going up walls and be upside-down.
- Capable of walking into creases (>90 degree difference between floor and wall). Probably needs a "front" raycast test to detect approaching wall surfaces
- Whole body rotation system, can provide a target orientation and the body will rotate using the correct angular forces, some bounce is desired but should be minimal. Incorporate leg movement for turning, limiting turn rate until legs can follow.
- Some way to disable/ counteract gravity, possibly depending on grounded legs. An overcomplicated solution is to draw a plane using the grounded legs, and intersect a ray from the "center of mass" towards the nearest position of the polygon, and applying a gravitational resistance at that intersection point, allowing the body to rotate (fall over), and the legs to move to stay upright.

# Plan
- [x] Test using Joint3D to connect rigid body to PhysicalBone3D?
- [x] Ground velocity can move leg targets when leg is in contact with ground
- [x] DESTRUCTION TIME
- [x] Make legs act on the physical locations of the skeleton and not IK state
- [x] Add bool to CrawlerCharacter to disable physical system and use IK only, so that testing can compare the two for accuracy. Ideally the physical system should only add reaction forces to legs and not have much affect on movement ability.
- [x] Friction needs to be solved after legs update ground state, and applied locally to the "ground" leg body in physics mode, or the main body in virtual mode, for rotation and linear acceleration, rather than applying friction as a whole to the main body.
- [ ] Change leg step behavior to be mostly an internal state, and act when unexpectedly removed from the ground. Legs should not pay attention to any step parameters of other legs, only the ground and comfort state. In fact it is probably best to think of steps as roughly asking its neighbors "hey, are you okay if I were to intentionally come off the ground?" then neighbors should say yes or no using simple logic questions about itself and its neighbors.






# TODO NOW FOR LEG PHYSICS
Slap slider joints on each child joint of the IK chain, update their Z rotations to match the IK z rotation of the first joint, allow plenty of pitch and length to not interrupt the legs normal function. This effectively adds 3 more joints purely to control and pass Yaw to the main body. Give high priority so they all act before regular joint corrections.






Goals of a leg
1. Stay comfortable
2. Stay on the ground

Algorithm
0. Search for suitable ground
1. If the leg is comfortable and grounded...
    1. If `ground_time` is larger than `X * InputManager.PHYSICS_TICKS`...
        1. If suitable ground is available AND further than `early_step` distance...
            1. Ask all pairs (Pair Query), if OK...
                1. Ask all neighbors (Neighbor Query), if OK...
                    1. Target suitable ground (take a step)
                    2. Set `target_is_ground` to `true`
                    3. Terminate
    2. Stay on ground
    3. If `drag_time` is positive...
        1. Decrement `drag_time` by `3`
    4. Terminate
2. (Not Comfortable OR Not Grounded OR Both)
3. If not grounded...
    1. If `drag_time` is positive...
        1. Decrement `drag_time` by `2`
    2. Reason: Floating
    3. If suitable ground available...
        1. Target it (take a step)
        2. Set `target_is_ground` to `true`
        3. Terminate
    4. Target comfortable lifted position (temporary lift)
        - Future: Expand search for suitable ground
    5. Terminate
4. (Grounded and Not Comfortable)
5. If suitable ground available...
    1. Ask all neighbors for permission to leave the ground (see next section)
    2. If all neighbors are OK...
        1. Target it (take a step)
        2. Reason: Not Comfortable
        3. Set `target_is_ground` to `true`
        4. Terminate
    - Future: Expand search for suitable ground
6. Either some neighbors are in disagreement, or no available ground.
7. If current `ground_rel_con_velocity.dot(body.ground_direction)` is at least half of `body.ground_direction.dot(body.ground_velocity)`...
    1. Increment `drag_time` by `2`
    2. If `drag_time` exceeds `2 * X * InputManager.PHYSICS_TICKS`...
        1. Reason: Dragging
        2. If suitable ground available...
            1. Target it (take a step)
            2. Set `target_is_ground` to `true`
            3. Terminate
        3. Target comfortable lifted position (temporary lift)
        4. Terminate
8. Otherwise, if `drag_time` is positive...
    1. Decrement by `1`
9. Terminate

Pair Query:
1. Lookup `paired` legs from CrawlerCharacter cache
2. Initialize value `pair_inactive` to `true`
3. For each valid leg, if...
    1. `target_is_ground`...
        1. `target_time` is less than some value...
            1. Reason: Sync with leg
            2. Return OK
        2. Set `pair_inactive` to `false`
4. If `pair_inactive`...
    1. Reason: Early Step
    2. Return OK
5. Return DISAGREE

Neighbor Query:
1. Lookup `anti_paired` legs from CrawlerCharacter cache
2. For each valid leg, if...
    1. It is performing a temporary lift...
        1. Return DISAGREE
    2. It is targeting suitable ground...
        1. Return DISAGREE
    3. It is not comfortable...
        1. Return DISAGREE
3. Return OK

Ground Time:
- Reset to `0` when `is_grounded` is `false`
- Reset when targeting new ground (take a step)
- Reset when targeting lift position (temporary or forced)
- Increment by `1` while grounded and no targets

Target Time:
- Reset to `-1` when reaching a target
- Increment by `1` while traveling to target

Target Is Ground:
- Reset to `false` when reaching a target

Leg Target:
1. Initialize `new_position` to `target.position`
2. Compute `z_axis_swing_angle` between `target.position` and `current_target` from the first IK bone in the leg chain
3. Rotate `new_position` by `signf(z_axis_swing_angle) * minf(absf(z_axis_swing_angle), swing_rate)`
4. Rotate `target.position` by `z_axis_swing_angle`
5. Compute `x_axis_swing_angle` between `target.position` and `current_target` from the position of the 'last' IK bone in the leg chain
6. Rotate `new_position` by `x_axis_swing_angle` similarly to the previous z-axis swing
7. Rotate `target.position` by `x_axis_swing_angle`
8. Compute a linear travel using the arc length using a radius from the first bone in the chain to `target.position` and angle of `swing_rate`, without passing through the point. Apply the linear travel to `new_position`.
9. Set `target.position` to `new_position`

What happens now
1. `_integrate_forces()`
    1. `_update_ground()`
        1. leg update
    2. `pose_updated()`
    3. Forces are applied to the body
2. PHYSICS TICK

What I want to happen

1. `_integrate_forces()`
    1. `_update_ground()`
        1. `leg.pre_update()`
            1. `_update_grounded()` (update leg ground state)
        2. `leg.check_early_step()` (early step state)
        3. `leg.update()` (stepping & move leg targets)
        4. `skeleton.advance()` (update IK)
            1. `leg_pose_updated()`
                1. `pose_updated()` (calculate leg velocity)
    2. `_calculate_ground_vectors()`
    3. `_custom_pre_movement_forces()`
    4. Desired motion applied
2. PHYSICS TICK

- [ ] Use SpringCast3D (and probably improve it?) for maintaining ground contact and softening impacts on the legs. Right now legs just hover above the ground or rigidly collide and push the entire body off balance from IK. This solves a disconnect between where the leg colliders impact the ground and where IK wants to place them. Also allow disabling grip when the leg needs to change footing position. Make sure to iterate the forces as 6 springs would otherwise probably over-accelerate, iterating would allow damping to equalize the forces as both bodies would incur huge initial acceleration each frame.
- [ ] Fix walking on the wrong side of surfaces, virtual clipping. One idea is to ray trace along the bones of the chain, and if it intersects anything but the crawler bodies, ignore any ground cast contact. If it hits the main body, consider it a good ground.

# Current Plan
- [x] Update joints array to be in chain-order, so forward iteration is root-to-end and backward iteration is end-to-root. When a joint is destroyed, it should be deleted, and child joints should be "disabled" and removed from iteration list, and parents should be set to "non-functional" and target some "safe" rotation.
- [ ] Calculate an iterated motor velocity by running up and down leg chains. Odd iterations run from end to root, even iterations run root to end. Errors determine velocities, and velocities incur additional proportional errors on the next higher and lower joint angles. Test one, two, and three iterations to see how quickly velocities converge. Experiment with a "baumgarte" factor to see if it improves convergence rates.
- [ ] Make positional constraints on joints attached to the main body work properly, they should not cause legs to detach when offsets become large. May need an iterative approach or just limit the maximum change allowed each tick.
- [x] Leg behavior should be effectively disabled when joints are destroyed, IK should be disabled for the entire chain and motors set to 0 target velocity with low force limit to simulate disabled motors that only have friction.
- [ ] Copy angular limitations to joints from the IK settings

# Walking Improvement Ideas
- [ ] Improve leg step location logic, allow sweeping a larger space and track the best location for the next step or the rest of the leg. Probably some evaluation function that compares the current leg location with the best leg location, and if the current position is bad, move to the best one.
- [ ] When shape step cast safe length increases, you must perform an origin-to-origin raycast from the old step and the new step. If it fails, increment a counter and delay to the next tick. This counter represents the segments of a raycast path from the current step target to the next target, following path the leg target would take, when a valid path is found then update the step target. If the length decreases, assume it is safe to use as a step target (a leg closer to the body is always better than a leg stuck on the wrong side of a wall).
- [ ] For "simple" solution, if the path takes >45 angle change, run an "animation" which just replays a set acceleration sequence that hopefully gets it flat on the wall it was approaching.
- [ ] Convert the magic number for leg speed multiplier to an iterative value that increases up to 2.0 while legs are dragging, and decreases to 1.0 while legs are not dragging. Should be able to stabilize leg speed to account for small differences across the legs to minimize dragging.

# Body Orientation
- There is a desired pitch and roll determined by the target positions of each leg. This will be called the desired body plane.
- The body can pitch up/ down by some limited angle, relative to the desired pitch.
- The body always tries to correct for roll.
- To calculate the yaw, take the current forward and the goal forward, flatten to the desired body plane, and take the signed angle between them on the normal (up) axis of the desired body plane.

1. If no legs are in contact with the ground, do not do any rotation calculation. FOR LATER: apply damping as if by friction with the air.
2. Calculate a preferred forward using the vector pointing from the back legs to the front legs. If the leg is grounded, use its current target position. If it is not grounded, use the current collision point of the step target. If there is only one leg missing, use its rest position. If there are more than one missing, use the current forward and right as the preferred vectors.
3. Calculate a preferred right using the vector pointing from the left legs to the right legs, unless more than one are missing as above.
4. From these, cross to obtain a preferred up vector pointing away from the ground.
5. From these vectors, obtain a Basis on which all rotations will be calculated and applied.
6. If all legs are either moving or comfortable (that is, no legs are both not comfortable and not moving), then compare the target direction with the transverse plane (Y+) to determine if yaw rotation is allowed (cardiod formula). If so, take the signed angle between current forward and target direction on the preferred up axis. This will be the yaw angular target.
7. Take the signed angle between the current right and the preferred right on the preferred forward axis. This will be the roll angular target.
8. Take the signed angle between the current forward and the preferred forward on the preferred right axis. This will be the pitch angular target. FOR LATER: take the dot of the target direction and the preferred up to obtain a signed angle. Clamp this to a min and max pitch angle. Multiply by (PI - yaw) / PI. This will be the pitch angular target.
9. ~~Obtain a quaternion (pitch, yaw, roll), this will be the `Difference` quaternion. Obtain a quaternion from the current Basis, this will be the `Current` quaternion. Obtain a "conjugated" quaternion by this operation: `Current.mult(Difference).mult(Current.inverse())`. Obtain euler angles from the resulting quaternion. This will be the `angular` vector.~~
10. Divide the `angular` vector by the delta time, this will be the `max_angular` allowed for the current step.
11. Obtain a `limited_angular` vector by multiplying the sign of the `angular` vector with the min between the `max_angular.abs()` of the current step and the rotation rate parameter multiplied by the inverse overshoot parameter.
12. Rotate the `limited_angular` vector by the current Basis. This will be the `target_angular`.
13. Move the angular velocity towards the `target_angular` vector, multiplied by the `overshoot` parameter, using an acceleration multiplied by the grounded leg factor. The grounded leg factor is the number of grounded legs over the total leg count.
14. As a final step, if the rotated limited vector is approximately zero, and the angular velocity is less than 0.5 degrees per second, set the angular velocity to zero.

# IK Limiting
- When the bone transforms are computed, compare the end bone position to the `global_ik_target` position. If the distance is greater than some small constant distance, teleport the `target` node to its end bone and "lock" the `target` node such that it maintains the current local offset from the crawler body.

# Relative Steps
Steps will use vectors and rotations + length interpolation. The process is like so:
1. Take the current position of the leg as a flat vector pointing from the attachment of the leg to the leg end bone. This is the leg angle+distance vector.
2. Take the vector pointing from the attachment to the step target, this is the target angle+distance vector.
3. Rotate the leg vector towards the target vector, then move its length towards the target vector's length. This should produce a perfect swing and distance interpolation, as if it was actual robotics at work.
4. Have a `swing_amount` parameter, that while I cannot prove it, I believe it will give nice enough results. When less than `0.0`, skip rotations and everything and just move the point to the target in a straight line. When less than `1.0`, create the plane using one of the endpoints and the normal created by crossing the vector pointing from the current to the target with the up vector. Interpolate the length of the rotated vector to its point on that plane using `1.0 - swing_amount`
5. Compute how much rotation should happen by taking the current leg speed in meters-per-second over the length of a 90-degree arc with a radius of the rest position of the leg, then multiply by PI/2.0 to get the radians-per-second.

# Physical Skeleton Procedure
1. Copy physical joint rotations to skeleton pose
2. IK runs with physical joint pose
3. Update motors of joints to target IK pose