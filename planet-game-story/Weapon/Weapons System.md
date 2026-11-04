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
- Parameterize things with resources, all weapons should just be a list of slider that the weapon script uses. Resources ARE the weapons, they hold ammo state and remember it. Makes it possible to duplicate a weapon and change parameters in real-time.
- Every weapon should be strong in its use-case
- Any weapon can get the job done
- Be able to experiment without harsh punishment
- Debug tools at the beginning

# System Idea
- One sidearm slot reserved for the main sidearm, which cannot be removed.
- Second sidearm slots: can hold future tool, security gun, or sword
- Two large weapon slots on the back: can hold rifle, security gun, or shotgun
- The player is restricted to three weapons, plus the sidearm.
- When getting the story weapon, it takes a back slot and cannot be removed.

# Recoil methods
- No recoil
- Tilt camera up while firing
    - Recover when no longer firing? Could actually be fine on keyboard/ mouse... (not necessary with controller)
    - Can also rotate weapon side-to-side during this
- Follow animation spline while firing, with a loop point, recover when stopped
- Impulses displace weapon while firing, recovering displacement over time

# Damage Algorithm
```py
structure = 100
armor = 100
max_armor = 100

def damage(dmg):
    global armor, max_armor, structure

    armor_dmg = round(
            dmg * (1.0 - ratio)
            * math.sin(math.pi * (armor / max_armor) * 0.5)
    )
    armor = max(0, armor - armor_dmg)
    pen_dmg = max(0, dmg - armor_dmg)
    structure = max(0, structure - pen_dmg)

    print('Armor:', armor, '\nStructure:', structure)
```

# Weapon Resource Parameters
- Damage per hit
- Hits per shot (e.g. 10 for shotgun, 1 for everything else)
- Maximum reserve count, extra ammo capacity
- Ammo count, capacity of the weapon
- Reload time
- Armor penetration ratio, `0.0 - 1.0`
- Hit spread range (e.g. 5 degrees for shotgun)
- Shock damage per hit (robots can be killed when accumulating too much shock)
- Melee
    - Melee-only flag (e.g. for the sword)
    - Melee damage
    - Melee time (how long the attack is active)
    - Melee cooldown (reset timer before the weapon can be used again)
- Sound
    - Audible range (in meters)
- Recoil
    - TODO: probably want a two-point pivot to make weapons rotate at a grip-point, in addition to a larger overall pivot at the elbow or shoulder point
    - All accelerations are biased in the current velocity direction
    - Linear acceleration
    - Linear variability (random angle)
    - Linear velocity damping (percentage per second that velocity decays)
    - Linear recover rate (percentage per second that displacement decays)
    - Max linear displacement
    - Angular rise acceleration
    - Angular variability (random angle)
    - Rise angle bias (vertical angle offset of recoil)
    - Angular velocity damping (percentage per second that velocity decays)
    - Angular recover rate (percentage per second that displacement decays)
    - Max cone angle
    - Pivot point, where rotation is determined (relative to weapon node origin)
- Key Weapon flag
    - Key weapons cannot be removed from the inventory, only moved to different slots
- Size flag
    - Small, can be stored in medium slot
    - Medium, can be stored in medium and large slot
    - Large, can be stored in large slot
- Automatic flag (fires continuously while triggered)
    - fire rate, converted to physics ticks (display in editor with true fire rate)
- Charge flag (holding will bank shots, fired when released)
    - maximum shots, ignored when Lock-on flag is active
    - charge rate (e.g. 2 shots per second), ignored when Lock-on flag is active
    - activation time (e.g. 0.5 seconds before first charge)
    - fire delay, converted to physics ticks (display in editor with true delay)
    - fire rate, converted to physics ticks (display in editor with true fire rate)
    - if fire rate exceeds 1 per tick, then it will batch multiple in a single tick
    - cooldown time (e.g. 0.3 seconds per shot fired)
- Lock-on flag (will target enemies within a cone)
    - maximum targets, overrides charge max shots when active
    - target cone angle (only targets within cone)
    - selector for closest targets or strongest targets
    - target acquire rate (e.g. 2 targets per second), overrides charge rate when active

# Game Interactions
- Animations
- Have a visual scene, includes arms
- Particle/ light effect
- Sounds
- Raycast for projectiles, hitbox for melee
- Melee could support raycast for decal placement, but focus on hitbox for impact
- Tell entities about damage (and other details for dismantle, [[The Sword]])
- Tell entities about stun from [[Future Tool]], the entity will decide what to do
- Damage types: piercing, stagger ([[Shotgun]]), stun and charged stun ([[Future Tool]]), structure (dismantle), critical (piercing-structure type, spreads remaining damage to connected parts, [[Ultra Weapon]]).
- Input for "pressing/ not pressing the button" (no return values)
- Charged behavior, what that does
- Must know if it has ammo, and is loaded
- Input for "reload" (do not return anything)
- Provides a Control node for Player to put in their UI, for ammo status
- Control node for targeting (reticle, [[Ultra Weapon]] target system)
- Switches to disable unused elements, to be used for enemies/ multiplayer. Disables ui updates, disables ammo tracking, purely input driven. For example, a "sidearm" can be given to a weak enemy and it just shoots it without reloading or ui.

# Want This
- [[Shotgun]] is for crowd control, can stun fast enemies and take down groups of weak enemies. Can dismantle robots very quickly.
- [[Rifle]] is good for any enemy, but only the best for a few
- [[Sidearm]] is good for single targets when conserving ammo
- [[Security Gun|Sec. Gun]] is good for sweeping weak-spot enemies, such as needing to hit several weak points rapidly to quickly destroy
- [[Future Tool]] is a utility weapon, can fire multiple shots to quietly disable a robot, or charged up to deal huge damage after a timed delay
- [[Ultra Weapon]] is a type of railgun that can target lock several enemies by holding the trigger. It can be fired normally for precision shots. It travels through enemies, amplifying damage in a sort of cone shape. Like bowling with robots.
- [[The Sword]] cuts through any metal with ease, can be swung to dismantle any robot. Dismantling, of course, is completely destructive to the bots. It has no ammo, but is only effective for larger targets that you can get close to.
