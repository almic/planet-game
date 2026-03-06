
# Do NOT do this
- No interface classes/ objects. Scripts which purely manage interaction with another script. Just make an API in the class itself.
- Functional animations, animations which read from or modify game state. Animations must be prepared and kicked off by the relevant system.
- Start writing unplanned code, if something comes up then you must carefully consider it and how it impacts the rest of the game.

# DO this
- Know the system in as much detail as possible, and all interaction points, before writing code.
- Consider diagramming execution if something isn't obvious.
- Put input processing into frames, game logic into physics. This should make multiplayer support easier.
- Always create visual debug tools alongside any complex system
