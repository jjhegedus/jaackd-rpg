# jaackd-rpg — Claude Code Guide

## Project Overview

A procedurally generated RPG built with Godot 4. Terrain intervisibility is a core mechanic
driving encounters, wilderness navigation, ambush detection, and fog of war.

## Technology

- **Engine:** Godot 4 (GDScript primary; C# if performance demands it)
- **Language:** GDScript unless a system is performance-critical
- **Data format:** Godot Resources (.tres/.res) for game data; JSON for external/editable data

## Directory Structure

```
jaackd-rpg/
├── assets/              # Imported assets only — do not hand-edit .import files
│   ├── textures/
│   │   ├── terrain/
│   │   ├── characters/
│   │   ├── items/
│   │   └── ui/
│   ├── audio/music/ & sfx/
│   ├── fonts/
│   └── shaders/         # GLSL / Godot visual shaders
├── scenes/              # .tscn files — structure mirrors scripts/
│   ├── world/
│   ├── characters/
│   ├── ui/
│   └── items/
├── scripts/             # GDScript organized by domain
│   ├── world/
│   │   ├── generation/      # Procedural terrain, biomes, dungeons, encounters
│   │   ├── intervisibility/ # Viewshed, LOS, fog-of-war computation
│   │   └── navigation/      # Pathfinding, traversal cost, high-ground logic
│   ├── characters/
│   │   ├── player/
│   │   └── enemies/ai/
│   ├── systems/
│   │   ├── combat/
│   │   ├── inventory/
│   │   ├── quests/
│   │   └── dialogue/
│   └── utils/           # Math helpers, noise wrappers, geometry utilities
├── data/                # Authored game data
│   ├── biomes/
│   ├── encounters/
│   ├── items/
│   └── enemies/
└── addons/              # Third-party Godot plugins (committed to repo)
```

## Core Systems

### Procedural Generation (`scripts/world/generation/`)

- Terrain is generated from layered noise (FastNoiseLite recommended).
- Biomes determined by elevation + moisture maps.
- Encounter tables are biome-scoped and modulated by visibility state.
- Dungeons/structures placed via BSP or WFC on top of terrain.

### Intervisibility (`scripts/world/intervisibility/`)

This is a **primary mechanic** — treat it as a first-class system, not a utility.

Key concepts:
- **Viewshed:** the set of terrain cells visible from a given position and elevation.
  Computed via ray-march against the heightmap (Bresenham 3D or similar).
- **Line of Sight (LOS):** binary check between two specific points.
- **Encounter triggering:** enemies spawn / become active when their viewshed
  overlaps the player's position (or vice-versa).
- **Navigation cost:** paths that cross exposed ridgelines cost more (or are avoided
  by cautious AI agents).
- **Fog of War:** persistent revelation layer updated from player's rolling viewshed.

Performance notes:
- Pre-compute static viewsheds for key terrain features (peaks, passes) at world-gen time.
- Cache player viewshed per chunk; invalidate on position change > N cells.
- For AI, approximate viewshed with a cheap elevation-adjusted cone before full LOS check.

### Navigation (`scripts/world/navigation/`)

- Godot's `NavigationServer3D` for agent pathfinding.
- Custom traversal cost weights for slope, terrain type, and intervisibility exposure.
- "Sneaky" AI paths prefer low-visibility corridors; "bold" AI ignores cost.

## Coding Conventions

- **Script naming:** `snake_case.gd`, one class per file.
- **Class naming:** `PascalCase` via `class_name`.
- **Signals:** declare at top of file, named as past-tense events (`player_spotted`, `chunk_loaded`).
- **No magic numbers:** use named constants or exported variables.
- **Autoloads/singletons:** only for truly global state (GameState, WorldManager, AudioBus).
  Prefer dependency injection or signals otherwise.
- **Scene composition over inheritance** — prefer small reusable scenes attached as children.

## What to Avoid

- Do not add UI polish, particle effects, or "nice-to-have" features before core systems work.
- Do not mock the procedural generation in tests — test against real generator output.
- Do not hand-edit `.import` files or `.godot/` cache files.
- Keep `addons/` lean — only commit addons that are actively used.

## Development Priorities (in order)

1. Heightmap terrain generation + chunked world loading
2. Intervisibility / viewshed system
3. Player movement + camera
4. Encounter system driven by intervisibility
5. Basic combat
6. Inventory + items
7. Quests + dialogue

## Useful References

- Godot 4 docs: https://docs.godotengine.org/en/stable/
- FastNoiseLite (built into Godot 4)
- Viewshed algorithms: Wang & Robinson (1994), XDraw, R3 — all adaptable to heightmaps
- Bresenham 3D line for cheap LOS: standard CG reference
