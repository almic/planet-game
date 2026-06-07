All the things I would like to do.

# Big Tasks

## Story
- [ ] Review and second draft of high level story
- [ ] Review and third draft of high level story
- [ ] List out levels and add to this list

## Enemies
- [ ] Finish the Crawler before starting any other enemy
- [ ] Plan out robots, make sure they have distinct shapes, sounds, and fighting style, they should match up with the three major weapons (Rifle, Security Gun, Shotgun) that are ideal for destroying them and what playing style is best
- [ ] I would like a larger (and maybe also a smaller) version of the Crawler, determine what is different about them and what they did before being hijacked
- [ ] Figure out what the behavior system will be for enemies. They should be as simple as possible. Please.

## Weapons
- [ ] Commit to a weapon inventory system. I think all weapons is best.
- [ ] Don't make any weapons until you have enemies to shoot
- [ ] Plan the weapon resource type and actually create resources for all weapons, this ensures you have the layout ready before you implement the system
- [ ] If you have enemies to shoot at, go ahead and start to write the weapon system
- [ ] Start designing the appearance and sounds of each weapon

## Levels
- [ ] Only start this when you have the third draft of the story and have a very good idea of what each level feels like
- [ ] Block out the flow of each level and when encounters happen, what enemies, and what weapons are available at that time. Levels have to be distinct in layout so things stay new and surprising.
- [ ] IDEA: when entering the super deep borehole facility, maybe have player place communication relays so they can maintain contact while underground. if this is done, then contact must actually drop out when entering dead zones.
- [ ] IDEA: doors that the player can open, introduce the doors and let the player find stuff. Put explosive robots in a room and make it obvious that only the robots are in the room. Set up the player to pass the room with enemies chasing, they could open the door and release the bombs on the pursuing robots. Don't just make this only for the one time, doors should be present in other places prior to this, and at least give two opportunities for the strategy (at different times, not back-to-back).
- [ ] IDEA: last few minutes of the game are very quiet and the player is alone. Must be a couple robots to fight, but remarkably few compared to the rest of the game. Starts the World Break and then you leave the planet.

## Dialogue
- [ ] Figure out what you will do

## Music
- [ ] Figure out what you will do

# FUTURE

- [ ] Create a collision layer named "stairs," and check if the floor layer matches. When it does, treat any normals as "uphill" normals, so that slope effects always slow the player. This prevents stairs behaving like ramps and more like stairs.
- [ ] Incorporate "inverse effective mass" when applying friction and movement forces to CharacterController, such that it proportionally shares accelerations (linear and angular) to ground and character bodies. This should fix the weird "sticking" to less massive objects from stopping friction, and should nicely apply counter-acting forces to the spinning platform (slows down/ speeds up depending on which way you run). Should also mean you can walk on the large ball and make it move beneath you.
- [ ] Add general air drag to all rigid bodies which uses collision shape meshes to approximate drag and ideally some lifting forces caused by localized vacuums
- [ ] Make launchers a more generic and usable "mover" which can be given an axis of movement or a path. It will travel along the path, correcting deviations in position using some max-force value. Remember last iteration's velocity and attempt to correct for any changes using a max force value, this allows it to accelerate against massive bodies pushing back on it. It should determine how much to accelerate by using it's own mass and the max force parameter, and not exceed the prior frame's velocity, probably using `move_toward()`.
