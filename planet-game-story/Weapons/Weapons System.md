# Do NOT do this
- Multiple ammo type per weapon
- Functional animations: animations which depend on the state of the weapon, or modify the state of the weapon
- Animation locking, use internal timers instead of waiting for certain animation states or animations to complete.
- Trigger mechanism
- Recoil sim
- Chambering/ charging sim
- Two weapons compete for relevance
- A weapon being almost useless for certain enemies
- Tutorial popups

# DO this
- Single weapon script (no inheritance, no components) that handles state and animation (but no functional anims!)
- Parameterize things with resources, all weapons should just be a list of slider that the weapon script uses.
- Every weapon should be strong in its use-case
- Any weapon can get the job done
- Be able to experiment without harsh punishment
- Debug tools at the beginning

# Game Interactions
- Animations
- Have a visual scene, includes arms
- Particle/ light effect
- Sounds
- Raycast for projectiles, hitbox for melee
- Tell entities about damage
- Input for "im pressing/ not pressing the button" (no return values)
- Must know if it has ammo, and is loaded
- Input for "reload" (do not return anything)
- Provides a Control node for Player to put in their UI

# Want This
- [[Shotgun]] is for crowd control, can stun fast enemies and take down groups of weak enemies. Can dismantle robots very quickly.
- [[Rifle]] is good for any enemy, but only the best for a few
- [[Sidearm]] is good for single targets when conserving ammo
- [[Security Gun|Sec. Gun]] is good for sweeping weak-spot enemies, such as needing to hit several weak points rapidly to quickly destroy
- [[Future Tool]] is a utility weapon, can fire multiple shots to quietly disable a robot, or charged up to deal huge damage after a timed delay
- [[Ultra Weapon]] is a type of railgun that can target lock several enemies by holding the trigger. It can be fired normally for precision shots. It travels through enemies, amplifying damage in a sort of cone shape. Like bowling with robots.
- [[The Sword]] cuts through any metal with ease, can be swung to dismantle any robot. Dismantling, of course, is completely destructive to the bots. It has no ammo, but is only effective for larger targets that you can get close to.
