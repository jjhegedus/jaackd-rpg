# JAACKD RPG — Player Guide

> **Status:** Early development. This guide reflects what is currently implemented.
> Controls and systems will expand as the game grows.

---

## Overview

JAACKD RPG is a procedurally generated tactical RPG built around **intervisibility** —
what your party can and cannot see from their position on the terrain drives encounters,
ambush risk, navigation decisions, and fog of war.

You command a party in turn-based play. Each turn you issue a march order; the party
executes it, and the world reacts to what they can see along the way.

---

## Views

The game has two views, toggled with **Tab**. The current view is shown in the
**top-right corner** of the screen.

| View | Description |
|---|---|
| **Tactical** | Overhead camera. Command your party, read terrain, issue orders. |
| **Entity** | First-person view from the selected entity's eye level. See exactly what they see. |

---

## Tactical View Controls

The tactical camera is always centred on the selected entity and follows it automatically.

| Input | Action |
|---|---|
| `W` / `↑` | Tilt camera toward overhead (increase pitch) |
| `S` / `↓` | Tilt camera toward horizon (decrease pitch) |
| `A` / `←` | Rotate camera left (yaw) |
| `D` / `→` | Rotate camera right (yaw) |
| `Scroll up` | Zoom in (lower camera height, down to eye level) |
| `Scroll down` | Zoom out (raise camera height) |
| `Right-click` | Issue march order to cursor position *(Planning phase only)* |
| `Tab` | Switch to Entity view |

---

## Entity View Controls

The entity camera is fixed to the selected entity's eye level (1.7 m above ground).
Use it to see exactly what the entity can see — useful for scouting sight lines.

| Input | Action |
|---|---|
| `W` / `↑` | Look up |
| `S` / `↓` | Look down |
| `A` / `←` | Look left |
| `D` / `→` | Look right |
| `Scroll up` | Narrow FOV (zoom in) |
| `Scroll down` | Widen FOV (zoom out) |
| `Tab` or `Esc` | Switch back to Tactical view |

---

## Turn System

Each turn cycles through three phases shown in the **status bar** at the bottom of the screen.

```
Planning  →  Resolution  →  (auto-returns to Planning)
```

| Phase | Description |
|---|---|
| **Planning** | Issue orders. Right-click terrain to set a march destination. |
| **Resolution** | The party marches. Status bar shows progress. Cannot issue orders. |
| **Review** | *(Currently auto-skipped)* Will show encounter results and events. |

---

## HUD (Heads-Up Display)

The top-left panel shows debug and status information for the selected entity.

| Field | Description |
|---|---|
| Health bar | Current / max health of selected entity |
| Coordinates | World position (x, y, z) in metres |
| Biome | Terrain biome at entity position |
| Terrain | Ground height in metres at entity position |
| Entity | Name of the selected entity |
| Cam pos | Tactical camera world position |
| Cam height | Camera height above terrain |
| Cam look | Camera look direction vector |
| Status bar *(bottom)* | Current phase / activity |
| View indicator *(top-right)* | Current view mode (TACTICAL VIEW / ENTITY VIEW) |

---

## Entity Visuals

Each entity in the world is shown as a **capsule** (1.8 m tall) in Tactical view.

- **Yellow capsule** — currently selected entity
- **Grey/white capsule** — other entities

Floating above each capsule is a **screen-space label** showing:

```
Name  Type
Role
```

Labels are hidden in Entity view.

---

## World Forge

Before playing you must create a world.

1. From the main menu select **World Forge**
2. Enter a **World Name** (required)
3. Optionally enter a **Town Name** and **Seed** (random if blank)
4. Click **Forge** — terrain generation runs in the background
5. When complete, return to the main menu and select your world to play

Worlds marked **[outdated]** were created with an older terrain format and should be
deleted and re-forged to pick up the latest terrain generation improvements.

---

## Entity Selection

- The **yellow capsule** marks the currently selected entity
- Only one entity can be selected (yellow) at a time
- Selection is set automatically to the first player character on load
- *(Clicking to change selection — coming soon)*

---

## Fog of War

Terrain is covered by fog until your party reveals it.

| Appearance | Meaning |
|---|---|
| **Very dark** | Never explored — your party has no information about this area |
| **Dimmed** | Explored but not currently visible — terrain is remembered but conditions may have changed |
| **Full brightness** | Currently in your party's line of sight |

The viewshed is computed from the selected entity's eye level using the actual terrain heightmap.
Terrain that is behind a hill or ridge will remain in fog even if it is close.

---

## What's Coming

- Clicking to change entity selection
- Encounter system — enemies appear when they enter your line of sight
- Regional LOD terrain rendering beyond the local chunk radius
