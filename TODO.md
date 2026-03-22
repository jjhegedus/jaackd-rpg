# TODO

Active work items in planned execution order. Completed items are in DONE.md.

| Status | Task |
|--------|------|
| **— Visibility System —** | |
| next | Switch tactical view from 3D overhead camera to 2D map: biome-coloured tiles + elevation contour lines (marching squares at world-gen) in a 2D SubViewport with pan/zoom; do this before building the four-state fog system so fog is built against the correct renderer |
| pending | Entity view: replace fog textures on 3D terrain with LOS occlusion + atmospheric white fog — geometry within LOS renders at full colour; world fades to white beyond entity's visibility radius; no fog-of-war darkening on 3D terrain |
| pending | Tactical view: four-state per-cell fog — Unknown (black), Remembered-seen (desaturated tiles, structure outlines only), Remembered-visited (desaturated tiles, names/detail), Visible (full colour); per-pixel on 2D map canvas |
| pending | Long-range viewshed: extend viewshed to cover line-of-sight at any distance — cells within LOS + fog radius transition from Unknown → Remembered-seen → Visible; high ground revealing distant terrain is a core mechanic |
| pending | Reframe `known_chunks` on EntityGroup as a coarse performance index only — tracks which chunks have any non-Unknown cells to skip per-cell fog queries on fully unknown chunks |
| pending | Entity vision stat on `Character`: named export, human baseline; affects atmospheric fog radius in entity view and viewshed range |
| pending | Character height modifier: taller entities see over obstacles and farther |
| **— Travel Targeting —** | |
| pending | Travel targeting: group can travel to any cell that is Visible or Remembered; Unknown territory only reachable via direction + duration fallback |
| pending | Travel command: click destination on tactical map overlay |
| pending | Travel command: direction + duration fallback input |
| **— Command Types —** | |
| pending | Rest command |
| pending | Attack command: show nearby visible enemies in command panel, select target |
| **— Tests —** | |
| pending | Extend `test_party_panel.json` with field assertions (`check` step) |
| pending | Test: command panel — verify groups listed, pending command shown, Ready button present |
| pending | Test: group restructuring — merge two groups, verify member list and ownership |
| pending | Test: encounter trigger — teleport party near enemy, assert encounter event fires |
| **— Multiplayer —** | |
| pending | Lobby scene: show unclaimed groups, allow claiming, respect WM-set caps |
| **— World Forge —** | |
| pending | World Forge WM path: entity creation, creature types, `player_selectable`, initial groups, player slots, caps |
| pending | World Forge player path: browse/claim assigned groups, party composition, character customization |
| pending | Move party selection out of in-game panel into session setup / lobby |
| **— Core Systems —** | |
| pending | Encounter system driven by intervisibility (depends on visibility system) |
| pending | Traversable / non-traversable geography |
| pending | Basic combat |
| pending | Inventory + items |
| pending | Quests + dialogue |
| **— Rendering / Visual —** | |
| future | Entity view: normal seam at local chunk boundaries — fix by stitching edge normals across adjacent chunks using neighbor edge heights; currently using `render_mode unshaded` as workaround |
| **— Future —** | |
| future | Tactical map memory distortion: apply Perlin noise to terrain/structure positions for remembered (seen/visited but not currently visible) cells — simulates imperfect memory |
| future | Tactical map camera: allow moving camera position to explore remembered/visited map areas beyond current entity position — bounded complexity, lower priority than open design questions |
| future | Tactical map detail levels: Remembered-visited shows names/population; Remembered-seen shows outlines only; maps as artifacts can elevate seen→visited-level information |
| future | Tactical map entity positions: size + distance rules (army of 10,000 visible at distance; small band on a mountain slope is not); deferred until core visibility system is stable |
| future | Window resize: recompute panel position/size when viewport changes |
| future | Formations: relative positioning within a group during movement |
| future | Army aggregation: groups of groups, higher-level command abstraction |
| future | WM "see everything" world-editing view (separate mode, design TBD) |
