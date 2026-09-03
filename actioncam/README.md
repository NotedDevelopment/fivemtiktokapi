# actioncam

A cinematic auto-director for NPC combat. Takes over the client's camera and continuously
picks the most interesting thing on the field to look at — whoever is shooting, whoever just
took damage, whoever just got a kill — cutting between close follow shots and fixed venue
cameras.

Built to make an NPC brawl watchable on a stream without anyone manning the camera. It is
**game-agnostic**: it knows nothing about TikTok, likes, or crews. Any resource can hand it a
list of peds and a set of camera placements.

Used by [`lms`](../lms/README.md) and [`tiktok`](../tiktok/README.md).

---

## Quick start

```cfg
ensure actioncam
```

```lua
-- client side, from your resource
exports['actioncam']:StartActionCam({
    center    = { x = 1695.0, y = 3762.0, z = 37.5 },  -- arena centre
    venueCams = Config.ArenaCameras,                   -- optional fixed cameras
})

exports['actioncam']:AddTrackedPed(ped, 4)   -- priority 4 = star of the show
-- ... later
exports['actioncam']:RemoveTrackedPed(ped)
exports['actioncam']:StopActionCam()
```

Standalone, without another resource driving it:

```
acamstart [x y z]     server console — start on all clients
acamstop              server console — stop on all clients
/arenaviewstop        client — stop locally
```

Both server commands require `source == 0` or the `tiktok.admin` ace.

---

## Exports (client)

| Export | Purpose |
|---|---|
| `StartActionCam(opts)` | Take over the camera. Hides HUD and radar. No-op if already active. |
| `StopActionCam()` | Release the camera with a 600 ms blend back to gameplay. |
| `IsActionCamActive()` | Boolean. |
| `AddTrackedPed(ped, priority)` | Register a ped as a camera candidate. `priority` defaults to `1`. |
| `RemoveTrackedPed(ped)` | Unregister. Also clears the ped's heat and drops it as the current target. |
| `ClearTrackedPeds()` | Unregister everything. |
| `AddPedHeat(ped, amount)` | Boost a ped's camera priority. Call this on a kill — `amount >= 60` makes it the guaranteed next shot. |
| `ForceAerial()` | Jump to the aerial mode immediately. |
| `ForceVenue(idx)` | Jump to venue camera `idx`. |

### `opts`

| Field | Type | Purpose |
|---|---|---|
| `center` | `vector3` or `{x,y,z}` | Arena centre. Used for the overview mode and to seed streaming focus. |
| `venueCams` | array | Fixed camera definitions — see [Venue cameras](#venue-cameras). Plain tables, so they survive net-event serialisation. |

### Net events

`actioncam:start` (with `opts`) and `actioncam:stop` are registered as net events, so a
server script can drive every client at once with `TriggerClientEvent`.

---

## How a shot gets picked

### Candidate selection

If any peds have been registered with `AddTrackedPed`, **only those** are candidates, and
they are filtered by strict priority tier — the highest non-empty tier wins outright:

| Priority | Convention used by `lms` |
|---|---|
| 4 | Viewer crew NPCs |
| 3 | Guards / attackers |
| 2 | Fodder |
| ≤1 | Default / fallback |

So while a single viewer NPC is alive, the camera never looks at fodder. When every tracked
ped is dead, the candidate list is empty and the director falls back to a venue camera.

If **nothing** has been registered, it scans `GetGamePool('CPed')` for armed, living,
non-player humans instead — which is what makes the standalone `acamstart` mode work.

### Heat

A background thread samples every candidate's health every 333 ms. Health loss adds to that
ped's `heat` score; heat decays by 15% each sampling cycle. `AddPedHeat` lets a game script
inject heat directly — `lms` calls it with `80` on the killer whenever an NPC dies, which is
above the `60` threshold that makes a ped an unconditional next pick.

### Ranking

Candidates are bucketed and the first non-empty bucket wins:

1. **Hot** — `heat >= 60`, or `heat > 8` while shooting. A ped at `heat >= 60` wins outright;
   otherwise one of the top 2 is chosen at random.
2. **Shooting**
3. **In combat**, not in cover
4. **In cover**, not shooting
5. **Idle**

### Cutting

A shot lasts `PedDuration` (5 s). If the subject is still *in action* — actively shooting
outside cover, or driving above 1 m/s — the shot is extended up to 3× that. When the timer
expires or the subject dies, the director re-ranks and cuts.

While on a venue camera, combat is polled every 400 ms; if a fight starts, it cuts straight
to the ped.

### Camera modes

| Mode | When |
|---|---|
| `ped` | Default. Follow-behind on foot, or a speed-scaled chase cam when the subject is in a vehicle. |
| `venue` | Filler when no tracked ped is alive, and the fallback whenever `advanceMode` has nothing to look at. |
| `aerial` | Hovers above the centroid of all candidates. **Disabled by default** (`AerialEvery = 0`) — reachable only via `ForceAerial()`. |
| `overview` | Fixed high orbit around `opts.center`. **Disabled by default** (`OverviewEvery = 0`). |

The `ped` mode does a shape-test from the subject toward the ideal camera position and pulls
the camera in if a wall is in the way, so it doesn't clip through geometry. It also calls
`SetFocusPosAndVel` on the camera position every frame — without that the engine only streams
assets around the player character and distant action renders as untextured blobs.

---

## Manual control while active

| Input | Effect |
|---|---|
| Left mouse | Previous ped in the candidate list |
| Right mouse | Next ped |
| `E` | Next ped |

Attack and aim are suppressed (`DisableControlAction` 24 / 25) so clicking to change the shot
doesn't make the streamer's character fire.

---

## Venue cameras

Fixed cinematic placements passed in via `opts.venueCams`. Four types:

| `camType` | Fields | Behaviour |
|---|---|---|
| `spin` | `location`, `radius`, `height`, `speed`, `fov` | Orbits `location` at a constant height. |
| `crane` | `location`, `radius`, `height`, `amplitude`, `craneSpeed`, `speed`, `fov` | Orbit plus a sinusoidal rise and fall. |
| `static` | `position`, `target`, `fov` | Locked-off shot. |
| `pan` | `pointA`, `pointB`, `target`, `speed`, `fov` | Dollies back and forth between two points. |

Any camera may also carry:

| Field | Purpose |
|---|---|
| `proximity` + `proximityPos` | The camera is only eligible **during action** if a fighting ped is within `proximity` units of `proximityPos`. Omit both to make it a downtime-only camera. |
| `label` | Display name, shown by the config tool. |
| `duration` | Recorded by the config tool but **not currently read** — cut timing uses the global `VenueDuration`. |

Cameras with a satisfied proximity check are preferred; if none qualify, one is picked at
random.

### Placing cameras in-game

The config tool (`configtool.lua`, gated on `ActionCamConfig.EnableConfigTool`) gives you a
freecam for placing venue cameras and exports them as pasteable Lua.

```
/acamconfig     enter / exit the placement freecam
/acamexport     dump placed cameras to F8 without leaving
```

| Key | Action |
|---|---|
| Mouse | Look |
| `W`/`A`/`S`/`D` | Fly |
| `Space` / `L-Ctrl` | Up / down |
| `L-Shift` | 5× speed |
| Scroll | Adjust fly speed |
| LMB | Place a camera of the current type |
| RMB | Preview the last placed camera / stop preview |
| `R` | Cycle type: SPIN → CRANE → STATIC → PAN |
| `E` | Export to console and exit |
| `Esc` | Exit without exporting |

`pan` needs two clicks — the first sets `pointA`, the second sets `pointB` and creates the
camera. Placed cameras are drawn as 3D markers with labels while you're in the tool.

Export prints a block ready to paste into `Config.ArenaCameras` (in `tiktok`) or
`Config.ArenaCameras` (in `lms`). It writes the geometry with sensible starting values for
`radius`, `height`, `speed` and `fov` — tune those by hand afterwards.

---

## Configuration

[`config.lua`](config.lua). Note this is the **camera behaviour**; the camera *placements*
come from the calling resource via `opts.venueCams`.

| Key | Default | Notes |
|---|---|---|
| `PedDuration` | `5.0` | Seconds on one subject before re-ranking. Tripled while the subject is in action. |
| `Fov` | `52.0` | Follow-shot field of view. |
| `FollowDist` / `FollowHeight` | `7.0` / `2.2` | Follow-behind offset. |
| `FollowSpeed` | `4.5` | Lerp rate. 2 is floaty, 8 is snappy. |
| `IdleOrbitSpeed` / `IdleOrbitRadius` / `IdleOrbitHeight` | `6.0` / `5.5` / `1.8` | See the note below — currently unused. |
| `AerialEvery` | `0` | `0` disables automatic aerial cuts. |
| `AerialDuration` / `AerialBaseHeight` / `AerialMaxHeight` / `AerialSpreadMul` / `AerialRadius` / `AerialSpeed` / `AerialFov` | | Aerial mode tuning. Height scales with how spread out the fight is. |
| `OverviewEvery` | `0` | `0` disables automatic overview cuts. |
| `OverviewDuration` / `OverviewRadius` / `OverviewHeight` / `OverviewSpeed` / `OverviewFov` | | Overview mode tuning. |
| `VenueProximityRadius` | `120.0` | Default proximity radius for venue cams that don't specify one. |
| `VenueDuration` | `10.0` | Seconds on a venue camera before returning to ped tracking. |
| `EnableConfigTool` | `true` | Set `false` on a production server — `/acamconfig` is not permission-gated. |

---

## Notes and gotchas

- **`EnableConfigTool` is not an actual guard.** The header comment says the tool "only loads
  when `EnableConfigTool = true`", but `configtool.lua` is listed unconditionally in
  `fxmanifest.lua` and `/acamconfig` has no permission check. Any player can enter the
  freecam. Set it `false` and verify, or remove the file from the manifest, before running
  this on a public server.
- **`idle_orbit` doesn't exist.** It's listed in the header comment's mode list, and
  `IdleOrbitSpeed` / `IdleOrbitRadius` / `IdleOrbitHeight` are in the config, but no such
  branch is implemented in `updateCam`. Idle subjects are handled by the normal `ped` mode.
- **Aerial and overview are off by default.** `advanceMode` deliberately never selects them —
  its comment reads *"aerial and overview sky views removed"*. They exist and work, but only
  via `ForceAerial()` / `ForceVenue()` or the `cycleCam` fallback when no candidates exist.
  Setting `AerialEvery` / `OverviewEvery` above zero does **not** re-enable automatic cuts.
- **The camera hides HUD and radar** for the duration and restores them on stop. If the
  resource is restarted while active, the client can be left with the HUD hidden until a
  manual `DisplayHud(true)`.
- **`opts.center` matters more than it looks.** It seeds `SetFocusPosAndVel` at startup and
  backs the overview mode. Passing it is cheap insurance against pop-in on the first shot.
- **All `exports['actioncam']` calls in `lms` and `tiktok` are `pcall`-wrapped**, so the
  resource is genuinely optional for both. If you write a new consumer, do the same.
