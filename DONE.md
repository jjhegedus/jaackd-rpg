# DONE

Completed work items, newest first.

| Date | Task |
|------|------|
| 2026-03 | `CommandPanel`: group restructuring UI — merge (absorb) and split in PLANNING phase; scroll/zoom conflict fixed (only consume scroll when mouse over panel); manifest saved on merge/split/rename; `test_restructure.json` automated test |
| 2026-03 | `HUD`: removed stale `get_active_command()` call; status bar shows "Resolving…" during RESOLUTION |
| 2026-03 | `main_menu.gd`: call `NetworkManager.start_offline()` on Play so TurnManager ready-gate fires |
| 2026-03 | `town_generator.gd`: townspeople set `player_selectable = false`; added `create_adventurer()` and `get_next_id()` |
| 2026-03 | `world_forge.gd`: generates 5 starting adventurers (warrior/ranger/rogue/cleric/mage) with `player_selectable = true` |
| 2026-03 | `game_world.gd`: auto-claims player_selectable groups for local peer in offline mode |
| 2026-03 | `CommandPanel`: replaces PartyPanel — group list with pending command per row, row-click selection, Execute/Continue button, hides during RESOLUTION |
| 2026-03 | `TurnManager`: `command_submitted(group_id)` signal; `CommandPanel` refreshes row on command change |
| 2026-03 | `TurnManager`: `submit_command(group_id, cmd)` — per-group pending command dict replaces `issue_command` |
| 2026-03 | `TurnManager`: per-peer ready flag; `set_peer_ready(peer_id)`; auto-starts execution when all peers ready |
| 2026-03 | `TurnManager`: all group simulations run simultaneously on one world clock; all pause on any event |
| 2026-03 | `TravelCommand`: added `group_id` field; commands carry their target group |
| 2026-03 | `NetworkManager`: added `PeerRole { PLAYER, WORLD_MANAGER }`, `local_role`, `_peer_roles` dict, `_rpc_announce_role` RPC, `is_world_manager()`, `get_local_role()`, `get_peer_role()` |
| 2026-03 | `EntityGroup` resource: group_id, display_name, owner_peer_id, member_ids, anchor_entity |
| 2026-03 | `Character`: added group_id field; ownership lives on group, not entity |
| 2026-03 | `WorldManifest`: groups array, next_group_id counter, `ensure_solo_groups()` (idempotent, migrates old saves) |
| 2026-03 | `WorldForge`: calls `ensure_solo_groups()` after character generation |
| 2026-03 | `EntityRegistry`: group table, `load_groups()`, `get_group()`, `get_group_for_entity()`, `get_all_groups()`, `get_groups_by_owner()`, signals `group_loaded`/`groups_cleared` |
| 2026-03 | `GameWorld`: calls `EntityRegistry.load_groups(manifest.groups)` at session start |
| 2026-03 | `DebugBridge`: `verify_groups` command; `run_test.py`: `check` step type with field validation |
| 2026-03 | `debug/tests/test_group_model.json`: 7/7 passed — 60 groups for 60 characters |
| 2026-03 | `EntityGroup.known_chunks`: regional chunk coords explored by the faction; populated from `FogOfWarManager._regional_explored` at session load; kept live on `regional_chunk_fog_updated`; refreshed on `group_restructured`; merge/split both inherit full fog knowledge |
| 2026-03 | `CommandPanel`: inline group rename — stable sort by group_id; `_notify_screen_ready` skips queued-for-deletion rows; `DebugBridge` `set_text` grabs focus; `press_key` sets both keycode + physical_keycode; `test_rename_group.json` 10/10 |
| 2026-03 | `DebugBridge`: `press_key` command; Label node type in `screen_ready` payload |
| 2026-03 | `debug/tests/test_party_panel.json`: automated end-to-end test — launch → main menu → play → open panel → assert labels |
| 2026-03 | `Log` autoload: file-based logging to `debug.log`, overwritten each run |
| 2026-03 | Party panel positioning fix: `set_anchor_and_offset` silently drops anchors for CanvasLayer children; switched to `get_viewport().get_visible_rect().size` + direct `position`/`size` |
| 2026-03 | Party panel: dark background, scrollable character list, Party/Town toggle buttons, per-character rows |
| 2026-02 | Procedural terrain generation (FastNoiseLite, layered noise) |
| 2026-02 | Chunked world loading / LOD system |
| 2026-02 | Heightmap-based terrain rendering with shader |
| 2026-02 | Biome determination (elevation + moisture) |
| 2026-02 | Town generation with named characters and roles |
| 2026-02 | Town markers (ring mesh + Label3D) |
| 2026-02 | Tactical overhead camera (TacticalCamera) |
| 2026-02 | Entity first-person camera (EntityCamController) |
| 2026-02 | TAB toggle between tactical and entity views |
| 2026-02 | Player movement (WASD + mouse) |
| 2026-02 | Character resource: display_name, role, creature_type, player_selectable, alive flags |
| 2026-02 | EntityRegistry: faction management, selection, position tracking |
| 2026-02 | EntityVisuals: capsule meshes and screen-space labels |
| 2026-02 | Fog of war: persistent revelation layer updated from player viewshed |
| 2026-02 | `WorldManifest` resource with versioned forge format |
| 2026-02 | `DiskManager`: save directory management, world listing, load/save manifest |
| 2026-02 | `WorldManager`: world initialization, chunk streaming |
| 2026-02 | `NetworkManager`: OFFLINE/HOST/CLIENT modes, ENet peer setup |
| 2026-02 | `TurnManager`: command queue, command_completed signal |
| 2026-02 | `WorldClock`: in-game time tracking |
| 2026-02 | `DebugBridge`: file-based command/event protocol, activated by `GODOT_DEBUG_BRIDGE=1` |
| 2026-02 | `debug/run_test.py`: JSON-driven test runner (launch Godot, drive steps, report pass/fail) |
| 2026-02 | `debug/wait_for_event.py`: standalone event listener utility |
| 2026-02 | `player_guide.md`: current controls and systems reference |
