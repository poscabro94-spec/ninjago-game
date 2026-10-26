# Ninjago game (Roblox)

All the scripts from `Place1.rbxl`, laid out for [Rojo](https://rojo.space) so they can live in Git and sync into Studio.

## Layout

| Folder | Goes into | What's in it |
|---|---|---|
| `src/ServerScriptService` | ServerScriptService | Spinjitzu server + bots + Tornado of Creation, parkour course, Golden Weapons server (tools, hits), elemental powers server, menu server (looks, bots, dummies), Time Blades server (time powers), shared HitEffects / StatusEffects (burn, shock, freeze) / TimeEffects (time lock) / TrainingDummy / SpinjitzuBots modules |
| `src/ReplicatedStorage` | ReplicatedStorage | Spinjitzu config / effect / elements / dragon, DragonModel (the Rising Dragon's meshes, generated: see below), older dragon mesh builder, NinjaAnimator (procedural player animations), GoldenWeapons (weapon settings, moves, two-handed arm IK), NinjaRoster (the characters in the menu), ElementPowers (power settings + arm poses) |
| `src/StarterPlayer/StarterPlayerScripts` | StarterPlayerScripts | Spinjitzu client (effects, flight, particle budget), parkour controls, Golden Weapons client (shuriken aiming), the menu (MENU button / M), elemental power controls + beam visuals |
| `assets/` | (import by hand) | `NunchuckGold.obj`: import with Studio's 3D Importer and put the model in ReplicatedStorage as `NunchuckGold`. `TimeGauntlet.obj` the same way (it comes in as a model `TimeGauntlet` with two parts, `Gauntlet` + `Blades`; the game moves it to ReplicatedStorage by itself). All Time Blades use it: a bronze gauntlet worn over the right forearm, the blades in each blade's colour |
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

## The Rising Dragon (`tools/dragon/`)

The dragon's head, jaw, neck plates and wings are designed in `tools/dragon/geometry.py` and written into `src/ReplicatedStorage/DragonModel.luau` by `build.py` (don't edit that file by hand). Each client builds the meshes from it at start (EditableMesh), so nothing has to be uploaded. To change the shape: edit `geometry.py`, check it with `python preview.py out` (the head) / `python scene.py out` (the whole dragon on a stand-in character, hovering + flying), run `python build.py`, and `python verify.py out` renders it again from the generated file with the game's own placement maths. Needs Python 3 with numpy + Pillow.

## Syncing with Studio

1. Install the Rojo plugin in Studio and the Rojo CLI (`aftman`, `rokit` or the release from GitHub).
2. In this folder run `rojo serve`.
3. In Studio: Plugins → Rojo → Connect. The scripts in the place are replaced with the files here.

The project uses `$ignoreUnknownInstances`, so models and parts already in the place (the imported nunchuck mesh, the map, etc.) are left alone.

## Versions

Every script has its version in the first line (e.g. `-- GoldenWeapons v4.6`). Bump it on every major change.
