# Ninjago game (Roblox)

All the scripts from `Place1.rbxl`, laid out for [Rojo](https://rojo.space) so they can live in Git and sync into Studio.

## Layout

| Folder | Goes into | What's in it |
|---|---|---|
| `src/ServerScriptService` | ServerScriptService | Spinjitzu server + bots + Tornado of Creation, parkour course, Golden Weapons server (tool, hits, training dummy) |
| `src/ReplicatedStorage` | ReplicatedStorage | Spinjitzu config / effect / elements / dragon, dragon mesh builder, NinjaAnimator (procedural player animations), GoldenWeapons (nunchuck moves) |
| `src/StarterPlayer/StarterPlayerScripts` | StarterPlayerScripts | Spinjitzu client (effects, flight, particle budget), parkour controls |
| `assets/` | (import by hand) | `NunchuckGold.obj`: import with Studio's 3D Importer and put the model in ReplicatedStorage as `NunchuckGold` |

File endings: `.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript.

## Syncing with Studio

1. Install the Rojo plugin in Studio and the Rojo CLI (`aftman`, `rokit` or the release from GitHub).
2. In this folder run `rojo serve`.
3. In Studio: Plugins → Rojo → Connect. The scripts in the place are replaced with the files here.

The project uses `$ignoreUnknownInstances`, so models and parts already in the place (the imported nunchuck mesh, the map, etc.) are left alone.

## Versions

Every script has its version in the first line (e.g. `-- GoldenWeapons v4.6`). Bump it on every major change.
