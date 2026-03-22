# Game Design

---

## Peer Roles

Two roles exist at the network level:

| Role | Description |
|------|-------------|
| `PLAYER` | Controls their assigned groups of entities. Subject to viewshed filtering during play. |
| `WORLD_MANAGER` | Controls their own assigned groups (world creatures, NPCs not assigned to players). Same play rules as PLAYER. Has additional capabilities in world-editing interfaces, which are separate from play. |

Role is established at session handshake and stored server-side. The server enforces role-based permissions; clients never self-report a trusted role.

---

## Network Modes

Handled by `NetworkManager` autoload (ENet/Godot multiplayer):

| Mode | Description |
|------|-------------|
| `OFFLINE` | Single-player, `OfflineMultiplayerPeer`. No network code runs. |
| `HOST` | This instance is the server authority + one local player (PLAYER or WORLD_MANAGER role). |
| `CLIENT` | Connects to a remote host. Receives filtered state. |

---

## Server Authority

The server is the single source of truth for all game state. Clients receive only what the server sends them.

**State filtering during play:**
- `PLAYER` clients receive state filtered by their owned entities' viewsheds (fog of war)
- `WORLD_MANAGER` clients receive state filtered by **their own entities' viewsheds** — WM is subject to the same viewshed rules as any player during play
- No runtime special-casing for WM role in the play code path

**Command validation:**
Every command (move, attack, restructure) is validated server-side:
```
group.owner_peer_id == requesting_peer_id
```
This applies symmetrically — WM cannot command player-owned groups, players cannot command WM-owned groups or each other's groups.

---

## WM Play View

The WM play view is **identical** to the player play view. The WM is a player with a different (potentially larger, more diverse) entity pool and a different role — not a different interface. Their elevated capabilities exist only in world-editing interfaces, which are separate from the play session.

This means:
- No special camera modes for WM during play
- No "see everything" during play
- No commands the WM can issue to entities they do not own
- WM's larger entity pool is just data — the game loop handles it identically

---

## World Editing Interfaces

World editing capabilities (entity creation, ownership assignment, party caps, group setup) are **authoring-time tools**, not play features. They live in separate interfaces:

- **World Forge (WM path)** — create creature types, create entities, set `player_selectable`, define initial groups, assign groups to player slots, set party caps
- **Session Setup (Player path)** — browse assigned/claimable groups, select party composition, customize character appearance and backstory

These interfaces are explicitly out of scope for the play scene. The play scene never surfaces authoring capabilities to any user.

---

## Lobby and Session Flow

1. WM publishes session (creates world, defines claimable groups)
2. Players join → lobby shows unclaimed groups (solo groups displayed as individuals)
3. Players claim groups — first-come-first-served within the available pool, subject to WM-set caps
4. WM claims their own groups in the lobby as well (WM is a participant, not just a host)
5. Session lock → play begins → group ownership is fixed for the session
6. **WM can override** group ownership after session lock (reassign, take back) — privileged action with deliberate friction in the UI

---

## Entity and Group Model

### Core Principle

**Groups are the unit of ownership and command.** Individual entities are always members of exactly one group. Groups carry the `owner_peer_id`; entities do not.

### Solo Groups

Every entity belongs to exactly one group at all times, including individuals. A single entity is wrapped in a **solo group** (a group of size 1). This is an implementation detail — the UI displays a solo group as if it were an individual entity (no group label, no group management UI shown).

This gives a uniform model: ownership, commands, and lobby claims all operate on groups. There is no dual-path logic for "is this standalone or in a group?"

### Data Model

**`EntityGroup` resource (new):**
```
group_id:       int           — stable unique ID
display_name:   String        — shown in UI when size > 1; hidden for solo groups
owner_peer_id:  int           — which peer owns this group (-1 = unclaimed)
member_ids:     Array[int]    — entity IDs belonging to this group
anchor_entity:  int           — entity ID that defines the group's map position
```

**`Character` resource (updated):**
```
group_id:       int           — which group this entity currently belongs to
(owner_peer_id removed — ownership is on the group)
```

**`WorldManifest` (updated):**
```
groups:         Array[EntityGroup]   — alongside existing characters array
```

### Group Transitions

All transitions are server-validated (`group.owner_peer_id == requesting_peer_id` for all affected groups) and only permitted during the **PLANNING phase**.

| Operation | Description |
|-----------|-------------|
| **Merge** | Two owned groups → one group. Old groups deleted. New group carries same `owner_peer_id`. |
| **Split** | One owned group → two groups. New groups carry same `owner_peer_id`. |
| **Transfer entity** | Move an entity from one owned group to another owned group. If source becomes empty, delete it. |

When a group is disbanded (all members removed), it is deleted. Solo groups are created automatically when an entity leaves a group and has no destination — each departing entity gets a new solo group inheriting the same `owner_peer_id`.

### Lobby Claim Flow

- The lobby presents all groups with `owner_peer_id == -1` and `player_selectable == true` on their members
- Solo groups appear as individuals in the lobby UI
- A player claiming a group sets `group.owner_peer_id = player_peer_id` for the entire group atomically
- WM claims their own groups in the same lobby flow — WM is a participant, not just a host
- WM can set a **party cap** per player slot, limiting how many groups or total entities a player can claim

---

## Command Model

**Commands are issued to groups, not individual entities.**

```
MoveCommand:    { group_id, target_position }
AttackCommand:  { group_id, target_group_id }
WaitCommand:    { group_id }
```

All entities in the group execute the command. A solo group receives commands identically to a multi-entity group — the model is uniform.

The UI may allow selecting an individual entity (e.g., to control the camera), but the command is always dispatched to the entity's group.

### Pending Commands

During PLANNING each group holds at most one **pending command** — the order that will execute when the ready gate opens. A group with no pending command is **idle**; it will not move during the next execution window.

Pending commands can be changed freely until the player marks themselves ready. Once the ready gate closes (all peers ready), commands lock and execution begins.

### Idle Groups

A player may hit Ready with one or more groups idle. Those groups sit still until the next planning window. This is a valid choice — a player may deliberately hold a group in reserve.

---

## Turn Phases

### Phase Cycle

```
PLANNING → (all peers ready) → RESOLUTION → (any group completes or is interrupted) → PLANNING → …
```

| Phase | Description |
|-------|-------------|
| `PLANNING` | Players issue pending commands to their groups. Group restructuring allowed. |
| `RESOLUTION` | All groups execute simultaneously on one world clock. No new commands accepted. |

PLANNING opens at session start and re-opens whenever **any** group's command completes or is interrupted (encounter, interlude). Groups that still have active commands continue running — only groups that completed or were interrupted must re-command (though any pending command may be changed during any planning window).

### Ready Gate

Each peer (player and WM) has a **ready flag**. The server transitions to RESOLUTION only when every connected peer has set their flag.

- A peer may set ready with idle groups — those groups sit still for the window.
- Once a peer sets ready their pending commands lock; they cannot change commands until the next planning window opens.
- The server starts RESOLUTION atomically when the last peer confirms ready.

### Simultaneous Execution

All groups across all peers execute on a single shared world clock. The simulation advances in uniform ticks; encounters are detected globally (any two groups whose paths cross within a tick trigger an event). When any event fires, the world clock pauses and a new planning window opens for all peers.

### Command Visibility

Pending commands are **private** to each peer until the ready gate closes. Once execution begins the server uses all commands for simulation; what is revealed to other peers is governed by viewshed rules (you see what your entities can see), not by the command data itself.

The `TurnManager` owns the phase state and broadcasts phase transitions to all peers.

---

## Ownership Enforcement Rules

1. A peer can only issue commands to groups they own (`group.owner_peer_id == peer_id`)
2. A peer can only restructure groups they own — both source and destination groups must be owned by the same peer
3. WM cannot restructure or command player-owned groups, even during their own planning phase
4. The server enforces all of the above — client-side enforcement is UX only, not trusted

---

## Commanding UI

The commanding interface is a collapsible right-side panel that replaces the party panel. It is visible during **PLANNING** and hidden during **RESOLUTION**.

### Layout

A single vertical panel on the right side of the screen:

- **Group list** — one row per owned group. Each row shows: group name, group size, pending command summary (or "Idle"). Click a row to select that group.
- **Selected group detail** — expands in place or below the list: member names, current position, pending command with edit options.
- **Command palette** — appears for the selected group: Travel, Rest, Attack, Wait/Idle.
- **Execute / Ready button** — anchored at the bottom. Marks this peer as ready; locks all pending commands. Becomes available any time during PLANNING (idle groups are valid).

### Group Selection

Groups are selected by clicking their row in the panel. The selected group receives any subsequent commands (right-click travel in tactical view, attack selection, etc.). The panel highlights the selected row. There is no left-click-in-world entity selection — the panel is the single selection point.

### Command Types

| Command | Target | Notes |
|---------|--------|-------|
| Travel | Known location on map, or direction + duration | See Group Knowledge System below |
| Rest | None | Group stays in place; simulates passage of time |
| Attack | Nearby visible enemy group | Only available when enemies are within group viewshed |
| Wait/Idle | None | Explicit idle — group sits still for the window |

When Travel is selected, the tactical map shows an overlay highlighting valid destinations (known/explored/visible chunks). The player clicks a destination or enters a direction and duration. Unknown areas are unavailable as destinations but are not blocked as direction targets.

### Group Management (PLANNING only)

Available from within the panel during PLANNING:

- **Rename** — edit group display name inline
- **Merge** — combine two owned groups into one (union of members and knowledge)
- **Split** — divide a group into two owned groups (both inherit full knowledge)
- **Transfer entity** — move one member to another owned group

All restructuring is PLANNING-only and server-validated (both groups must share the same `owner_peer_id`).

### Collapsing

The panel hides automatically when the phase transitions to RESOLUTION so it does not obstruct the action view. It reappears when PLANNING opens again.

---

## Group Knowledge System

Each group accumulates a persistent knowledge of the world — the set of locations they can travel to by name or map selection.

### Data Model

`EntityGroup` carries:
```
known_chunks:   Array[Vector2i]   — chunk coordinates this group collectively knows
```

Named locations (towns, landmarks) are indexed separately and become known to a group when any member has seen them.

### Knowledge Sources

- **Fog of war**: when a chunk is revealed by any member's viewshed, it is added to `known_chunks`
- **Named locations**: towns/landmarks seen by any member become permanently known
- **Group merge**: the merged group's `known_chunks` is the union of both source groups' knowledge

### Knowledge Propagation on Restructuring

When groups are merged or split, **both sides retain all knowledge**. An entity carrying knowledge of a trade route does not lose that knowledge when transferred to a new group, and the old group retains it too — the fiction is that knowledge was discussed and maps were exchanged.

### Travel Targeting

During PLANNING, when Travel is selected for a group:

1. **Known named locations** — always available as named destinations
2. **Explored chunks** — any chunk in `known_chunks` is a valid destination; shown on map overlay
3. **Currently visible chunks** — within the group's current viewshed; shown on map overlay
4. **Direction + duration** — always available as a fallback; the group moves in a bearing for a specified time, stopping at any chunk boundary that is not traversable

---

## Future: Formations

Groups will eventually support formation data (relative positions, shape, facing). This is intentionally deferred. The group model is designed to accommodate it:
- The `anchor_entity` field establishes the reference point for formation-relative positioning
- Formation data would be an optional resource attached to the group
- Movement commands with formation data would path all entities to their formation-relative target positions

## Future: Army Aggregation

The group model composes naturally to army scale:
- An **army** is a group of groups (or a higher-level abstraction over groups)
- Ownership and command semantics carry up the hierarchy unchanged
- Players with high entity caps can aggregate their groups into armies using the same merge/split operations

## Future: "See Everything" World Editing View

A separate world-editing interface will eventually allow the WM to see the full world state (all entities, all positions, unfiltered). This is **not** part of the play session. It will be designed as a distinct mode, entered and exited explicitly, with no overlap with the play code path.
