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
- [ ] Determine if a leg is actually grounded, use a shape intersection most likely
