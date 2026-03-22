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

---

#### Entity View — what the player sees in the 3D world

In entity view the camera is at eye level inside the world. Visibility is governed by two
independent factors that combine multiplicatively:

1. **Line of sight (LOS):** terrain occlusion via ray-march against the heightmap.
   Anything behind a ridge is invisible regardless of distance.
2. **Atmospheric fog:** a per-entity visibility radius beyond which the world fades to
   solid white (not black — the horizon becomes white haze, not a void).
   - Distance is measured from the *observer*, not the camera.
   - There is no grey-out or tinting of visible geometry — terrain within LOS at any
     distance looks normal until the fog threshold, then fades to white.

Future modifiers on the visibility radius (implement in this order when the time comes):
- **Character height:** a giant sees over obstacles and farther than a halfling.
- **Entity vision stat:** elves have a longer radius than humans; blind creatures have a
  very short one. This is a named export on `Character`, defaulting to a human baseline.

**Do not apply fog-of-war darkening to entity view.** The player is physically inside the
world; geometry that is within LOS should render at full colour. Areas beyond LOS or
beyond fog range simply disappear into white haze — they are not greyed, darkened, or
overlaid with a fog texture.

---

#### Tactical View — the overhead map

Tactical view is a **2D map** — not a 3D overhead camera. It is a genuine cartographic
representation of the world: biome-coloured tiles with elevation contour lines, rendered
in a 2D SubViewport with free pan/zoom. This is distinct from the entity view which is a
3D perspective camera.

Reasons for 2D over 3D overhead: fog states are per-pixel operations on a 2D canvas
(no shader special-casing per chunk); contour lines are generated once at world-gen via
marching squares; information overlays are 2D labels (no world-to-screen projection);
camera movement to explore remembered areas is a trivial 2D pan; no LOD complexity.

Each terrain cell (each heightmap grid square) is in exactly one of four states. Chunks
are loading/rendering units only — a single chunk will typically contain cells in all four
states simultaneously.

| State | Terrain rendering | Information shown |
|---|---|---|
| **Visible** | Full colour, accurate | All detail: terrain, structure positions, entity positions |
| **Remembered-visited** | Desaturated actual colours | Terrain + structure names, town population, named locations |
| **Remembered-seen** | Desaturated actual colours | Terrain + structure outlines only; no names or detail |
| **Unknown** | Solid black | Nothing |

Remembered-visited and Remembered-seen render identically (desaturated terrain colours —
not a flat grey overlay). They differ only in what *information* is displayed on top.
Physically visiting a location is required to know its name, population, or internal layout.
Seeing it from a distance gives you its shape and existence but not its details.

**Maps as artifacts (future):** A discovered map can elevate a Remembered-seen cell to
visited-level information (names, details) without requiring physical presence. Treat as
an information layer added on top of Remembered-seen, not a separate rendering state.

**Entity positions on the tactical map (future, design deferred):** Whether an entity
appears on the map depends on distance and size — you might see an army of 10,000 on a
distant plain but not a small band on a mountain slope. Size, distance, and terrain all
factor in. Do not implement rules for this yet.

Never conflate Remembered-seen, Remembered-visited, and Unknown — they represent
fundamentally different knowledge states even where rendering looks similar.

---

#### How viewshed drives tactical fog revelation

Viewshed is computed from the **active entity's position** only — not all group members.
This keeps per-turn computation bounded and enables the scout mechanic (see below).

Any cell within the active entity's LOS + fog radius transitions to Visible. Cells that
were Visible but are no longer within current LOS/radius revert to their remembered state
(Remembered-visited or Remembered-seen depending on history). Unknown cells that become
visible transition to Remembered-seen on next move if they leave the viewshed.

High ground advantage: an entity on a peak has LOS to many more distant cells than one
in a valley — the tactical map reveals more from elevation. This is a core mechanic.

Viewshed casts long-range rays to mark distant cells as seen. Local-resolution viewshed
is used for encounter detection; the same rays extended to full fog radius drive tactical
map revelation.

---

#### Group knowledge and the scout mechanic

Knowledge is per-group, not per-entity. Viewshed from the active entity updates the group's
fog state.

**On entity split (leaving a group):** the new solo group inherits a full copy of the
original group's knowledge. The scout knows everything the group knows when they set out.

**On entity merge (rejoining a group):** the returning entity's knowledge (original group
knowledge + new explorations) is unioned into the target group's fog state. The group gains
everything the scout observed.

This makes the scout mechanic organic: split off a fast entity, send it ahead, rejoin — the
whole group now sees what the scout saw. No special scout mode required.

---

#### Detection vs visibility

**LOS (terrain geometry)** is a prerequisite for detection but is not detection itself.
LOS is symmetric and purely geometric — it drives entity view rendering and is an input
to detection.

**Detection** is a separate system with additional modifiers: concealment (biome cover,
darkness, posture), pace, size. Detection is asymmetric — one party can detect another
without being detected in return. Do not conflate rendering visibility with detection.

---

Key concepts:
- **Viewshed:** the set of terrain cells visible from a given position and elevation.
  Computed via ray-march against the heightmap (Bresenham 3D or similar).
- **Line of Sight (LOS):** binary check between two specific points.
- **Encounter triggering:** enemies spawn / become active when their viewshed
  overlaps the player's position (or vice-versa).
- **Navigation cost:** paths that cross exposed ridgelines cost more (or are avoided
  by cautious AI agents).

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
