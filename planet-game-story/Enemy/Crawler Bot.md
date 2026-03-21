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
- [x] Make legs move together when one leg notices its pair/ partners are ready
- [x] Make them face target direction using angular forces
- [x] Fix weird pitch things where it tries to have a high pitch when the final pitch should be close to zero
- [x] Fix rest positions not rotating with the body
- [ ] Fix leg rotations over time, just apply some small correction to each bone's rest position every few frames
- [ ] Determine if a leg is actually grounded, use a shape intersection most likely
- [ ] Apply anti-gravity force based on legs in contact with the ground. At least half the legs must be in contact for full anti-gravity.
- [ ] Test wall climbing!
- [ ] Cache all leg neighbors when leg layout changes. Saves having to construct up to two lists each tick to check neighbors.
- [ ] ???

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
