Inspired from: https://youtu.be/t6mWwVTqZqY

1. Extend RigidBody3D
2. Restrict rotation of the body.
3. Use an elevated collider shape for stepping/ pushing. A capsule with the bottom around knee/ step-up height.
4. Collect input via interfaces, move, jump, etc.
5. Physics process adds linear velocity from input. "Brake" when not moving by damping velocity. Jump can apply impulse.
6. Integrate Forces will "spring" the body up from the ground using a shape-cast collision. Raycast may be acceptable for simpler entities/ third-person. Can collect the normal for sliding/ max floor angles.
7. EXTRA:
    - Could check for extreme impacts to "ragdoll"
    - Use force integration to up-right the body instead of using angle restrictions. Probably not needed if the inter-entity collision uses ragdoll parts, other colliders.
    - Use IK to place legs
        - Spider-like (source code) https://youtu.be/Hc9x1e85L0w

# Player
Player should extend CharacterController and pass inputs from Process. Player would also have a WeaponController as a child and pass inputs from process.
