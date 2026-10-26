# Ninjago game (Roblox)

All the scripts from `Place1.rbxl`, laid out for [Rojo](https://rojo.space) so they can live in Git and sync into Studio.

## Layout

| Folder | Goes into | What's in it |
|---|---|---|
| `src/ServerScriptService` | ServerScriptService | Spinjitzu server + bots + Tornado of Creation, parkour course, Golden Weapons server (tool, hits, training dummy) |
| `src/ReplicatedStorage` | ReplicatedStorage | Spinjitzu config / effect / elements / dragon, dragon mesh builder, NinjaAnimator (procedural player animations), GoldenWeapons (weapon settings, moves, two-handed arm IK) |
| `src/StarterPlayer/StarterPlayerScripts` | StarterPlayerScripts | Spinjitzu client (effects, flight, particle budget), parkour controls, Golden Weapons client (shuriken aiming) |
| `assets/` | (import by hand) | `NunchuckGold.obj`: import with Studio's 3D Importer and put the model in ReplicatedStorage as `NunchuckGold` |
| (your models) | (import by hand) | Golden Weapons: import with the 3D Importer and put them in ReplicatedStorage as `SwordOfFire`, `ScytheOfQuakes` and `ShurikensOfIce` (one shuriken). Until then placeholders made of blocks are used. The biggest part is the weapon; extra parts inside the model (e.g. red eye dots) keep their colour. Held by the wrong end: `FlipModel = true`; edge/blade facing backwards: `FlipEdge = true` (in `GoldenWeapons`) |

File endings: `.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript.

## Spinjitzu sounds (`tools/`)

`tools/spinjitzu-sounds.ps1` turns the Spinjitzu videos in `Videos` into `<Element> Start.ogg`, `<Element> Loop.ogg` (a seamless loop) and `<Element> End.ogg` in `Downloads\Spinjitzu Sounds`. You need ffmpeg (`winget install Gyan.FFmpeg`). Run it from this folder:

```powershell
powershell -ExecutionPolicy Bypass -File tools\spinjitzu-sounds.ps1 -FullOnly   # optional: each full soundtrack, to find cut points
powershell -ExecutionPolicy Bypass -File tools\spinjitzu-sounds.ps1             # cut all six
powershell -ExecutionPolicy Bypass -File tools\spinjitzu-sounds.ps1 -Only Ice   # redo one after changing its times
```

The cut points (in seconds) go in `tools/spinjitzu-cuts.csv`: `ClipStart` (wind-up begins), `LoopStart` / `LoopEnd` (the steady spinning part) and `ClipEnd` (the stop sound has died out). Leave a cell blank and the script guesses it from where the sound starts and stops. Then check `cuts used.txt` and adjust the times.

## Syncing with Studio

1. Install the Rojo plugin in Studio and the Rojo CLI (`aftman`, `rokit` or the release from GitHub).
2. In this folder run `rojo serve`.
3. In Studio: Plugins → Rojo → Connect. The scripts in the place are replaced with the files here.

The project uses `$ignoreUnknownInstances`, so models and parts already in the place (the imported nunchuck mesh, the map, etc.) are left alone.

## Versions

Every script has its version in the first line (e.g. `-- GoldenWeapons v4.6`). Bump it on every major change.
