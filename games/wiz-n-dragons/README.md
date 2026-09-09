# Wiz 'n' Dragons

A survival game about broom-riding wizards, spells and dragons in an endless sky. Built with Godot **4.7.2 .NET**, **C# / .NET 10** and **Forward+**.

## Run

Open `project.godot` in the Godot .NET editor, or run `./run.command` from this directory. Set `GODOT_BIN` to your Godot executable if needed.

## Play

| Control | Action |
| --- | --- |
| WASD / arrows | Fly |
| Left click | Fly toward a point |
| Space / Shift | Boost; release after exhaustion to recharge |
| Escape | Pause or resume |
| ×1 / ×2 / ×3 | Change simulation speed |
| F12 | Save a screenshot and telemetry to `evidence/` |

Flight has smooth steering, slight drift and a short coast after releasing movement. The camera follows through an open sky without screen wrapping or terrain collision. Menus pause combat and cloud motion.

Choose a wizard:

- **Ember:** starts with Fireball and casts faster while boosting.
- **Warden:** starts with Ward and periodically clears nearby hostile spells and pushes enemies away.
- **Arcanist:** starts with homing Arcane Orbs.

Defeat enemies for XP. Level-ups alternate between spells and wizard upgrades, starting with spells, with at most three choices. A maxed category is skipped; once both are maxed, levels offer healing. Each wizard has two spell slots, including the starter. Other spells include Tether, Runes and Lightning.

Potions restore up to 25 health and remain available at full health. Crystals grant 12 XP. Wind currents accelerate flight. Collected pickups stay depleted on revisits.

Survive until the Elder Dragon arrives at 22 minutes, then defeat it to win. You can continue exploring afterward. Upgrades reset each flight; silver and records persist. Silver spending is not implemented.

## Development

This project is an independent adaptation of Boats 'n' Beasts. `source/core` owns plain C# simulation and deterministic encounter chunks. `source/presentation` owns rendering, input, menus and effects. Cloud layers are decorative and use bounded caches.

See [art direction](docs/ART_DIRECTION.md) and [verification](docs/QUALITY.md). Combat tuning is an initial baseline and still needs balance work.
