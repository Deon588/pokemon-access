# Game checklist (needs a Pokémon Red or Blue ROM)

Run this once a ROM is in `~/Library/Application Support/Pokemon Access/ROMs`.
Each line names a PORTING.md section 7 step, what to do, and what the log
(`~/Library/Logs/Pokemon Access/pokemon-access.log`) must show. "speak via"
lines record every spoken text.

1. Ready on load. Open Pokemon Access. Expected: `hello from script`, `status:
   Connected to the script`, `speak via ...: Ready`.
2. Text. Press t on the title screen or in the first dialogue. Expected: a
   `speak via` line with the screen text (for example the copyright line or
   Professor Oak's introduction). Dialogue that appears while playing is spoken
   without a key press.
3. Map and position. After leaving the bedroom, press m then y. Expected:
   `speak via ...: Pallet Town` (or the current map), then the coordinates.
4. Objects. Press j, k, l repeatedly. Expected: object names and distances;
   shift j and shift l change the filter and announce it.
5. Pathfinding. Select an object with k, press p. Expected: a spoken path such
   as "3 down, 2 left"; shift p cycles the HM setting.
6. Battle HP. In the first battle press h then shift h. Expected: the enemy
   and player HP sentences.
7. Camera. Press d, g, r, v, f and the shift variants. Expected: `sound ...
   pass.wav` or `s_wall.wav` lines with pan values, and shift y reads the camera
   position.
8. Sound cues. Walk around. Expected: `sound ... s_grass.wav` or `s_default.wav`
   lines as your position changes (the footstep hook is emulated from position
   changes on mGBA 0.10.5).
9. Rename. Press shift k on an object. Expected: an alert with a Name field;
   typing a name and pressing OK speaks the object with its new name next time,
   and `names_red_blue_en.lua` appears in the Application Support folder.

Any Lua error is spoken as "Pokemon Access script error. See the log." and the
log holds `script error:` with the traceback; a Lua 5.4 incompatibility found
this way is fixed in the shim or recorded as a patch in PORTING.md 6.4.
