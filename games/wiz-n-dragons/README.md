# Wiz 'n' Dragons

A Godot 4.7.2 .NET / C# survival game using Forward+ and .NET 10. Independently duplicated from Boats 'n' Beasts, with an infinite open sky, procedural broom-riding wizards, dragons, and spells.

Run `./run.command`, or import `project.godot` into the Godot .NET editor. Set `GODOT_BIN` if your editor is installed elsewhere.

## Play

- WASD / arrows or left click: fly. The camera follows; there is no screen wrapping or terrain collision.
- Space / Shift: boost. Release after exhaustion to recharge.
- Escape: pause; menus pause combat and cloud motion.
- Level-ups alternate between spells and wizard upgrades, with up to three clickable rows. Two spell slots include your starting spell.
- Potions heal up to 25 health. Crystals grant 12 XP. Wind currents accelerate flight. Pickups stay depleted on revisits.
- Survive 22 minutes and defeat the Elder Dragon. Continue exploring after victory if desired.
- F12: save a native screenshot and telemetry. The ×1/×2/×3 button changes flight speed.

Choose Ember (Fireball, faster casting during boost), Warden (Ward, defensive pulse), or Arcanist (homing Arcane Orbs). Other spells include Tether, Runes and Lightning. Upgrades reset each flight; silver and records persist in this game's separate Godot user directory. Silver spending is not implemented.

## Structure

`source/core` owns plain C# simulation, combat, progression and deterministic encounter chunks. `source/presentation` owns Godot rendering, input, menus and effects. No runtime references to Boats 'n' Beasts are required.

Three decorative cloud layers scroll at different rates and stream bounded cells around the camera. A procedural distant sky shader adds slower atmospheric movement. Terrain, shore collisions, harbors and nautical art have been removed. Existing combat tuning is inherited as a starting point, not newly balanced.
