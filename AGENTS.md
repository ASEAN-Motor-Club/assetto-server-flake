# assetto-server-flake — Agent Guide

## Overview

A Nix flake that packages [AssettoServer](https://github.com/compujuckel/AssettoServer) (a custom .NET 8 Assetto Corsa freeroam/AI traffic server) as a NixOS module. Consumed as a flake input by the parent `amc-server` repository.

## Key Files

| File | Purpose |
|------|---------|
| `flake.nix` | Flake entry point — exposes `nixosModules.default` |
| `backend-options.nix` | NixOS option declarations (port, track, cars, AI, CSP, resources) |
| `assetto-server.nix` | Main NixOS module — binary packaging, config generation, systemd service |
| `logger.nix` | rsyslog log forwarding via imfile |

## Binary

AssettoServer is a self-contained .NET 8 single-file binary. The `fetchurl` downloads the release tar.gz from GitHub, and `autoPatchelfHook` patches the ELF binaries and shared libraries.

**Version:** Pinned via `services.assetto-server.serverVersion` (default: `v0.0.54`).
**Hash:** `sha256-EGc0S9ipjh+jV1xDpV3MnOZPTaIK5tttozVxXkGH428=`

To update the version:
1. Change `serverVersion` default in `backend-options.nix`
2. Download the new tar.gz and compute the hash:
   ```bash
   nix-prefetch-url --unpack https://github.com/compujuckel/AssettoServer/releases/download/<VERSION>/assetto-server-linux-x64.tar.gz
   ```
3. Update the `hash` in `assetto-server.nix`

If `autoPatchelfHook` fails on the .NET binary, fall back to `buildFHSEnv`:
```nix
assetto-server-bin = pkgs.buildFHSEnv {
  name = "AssettoServer";
  targetPkgs = pkgs: with pkgs; [ stdenv.cc.cc.lib openssl icu zlib ];
  runScript = "${assetto-server-raw}/bin/AssettoServer";
};
```

## Content Management

Tracks and cars live on the host at `/var/lib/ac-content/content/` and are bind-mounted read-only via symlink.

### Structure
```
/var/lib/ac-content/
  content/
    tracks/
      shuto_revival_project_beta/
        ai/              # AI splines (fast_lane.ai, fast_lane.ai.p)
        data/            # surfaces.ini, etc.
        ...
    cars/
      ks_toyota_gt86/
        data.acd
        ...
```

### Adding content
```bash
# Upload tracks
scp -r ./tracks/shuto_revival_project_beta root@asean-mt-server:/var/lib/ac-content/content/tracks/

# Upload cars
scp -r ./cars/ks_toyota_gt86 root@asean-mt-server:/var/lib/ac-content/content/cars/

# Upload AI splines
scp fast_lane.ai root@asean-mt-server:/var/lib/ac-content/content/tracks/shuto_revival_project_beta/ai/
```

Content changes require a service restart.

## Configuration

The module generates these config files declaratively at `preStart`:

| File | Source |
|------|--------|
| `cfg/server_cfg.ini` | `serverName`, `cars`, `track`, `port`, etc. |
| `cfg/entry_list.ini` | `cars` list + `aiTrafficSlots` AI entries |
| `cfg/extra_cfg.yml` | `extraCfg` attrset merged with defaults (YAML) |
| `cfg/csp_extra_options.ini` | Raw `cspExtraOptions` string |
| `cfg/admins.txt` | `admins` list (one SteamID64 per line) |

### AI Traffic

When `enableAi = true`:
- Player slots: `maxPlayers` entries in the entry list
- AI traffic slots: `aiTrafficSlots` entries with `AI=auto`
- `AiAutoFillCount` in `extra_cfg.yml` defaults to `aiTrafficSlots`

For SRP (Shutoko Revival Project): `aiTrafficSlots = 170` is typical.

### CSP (Custom Shaders Patch)

AssettoServer requires CSP on the client side. Set `cspMinVersion` to enforce a minimum version. Version `2584` = CSP 0.2.3+.

## Resource Allocation

Default CPU/memory isolation (non-overlapping with other game servers):
- Motor Town: cores 0-3
- BeamMP: cores 4-5
- AssettoServer: cores 6-7

## Deployment

```bash
# From amc-server root:
nix develop --command deploy root@asean-mt-server
```

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 9600 | UDP | Game traffic (configurable via `port`) |

## Limitations

- **Freeroam only** — AssettoServer does not support Race/Quali/Lap sessions
- **CSP required** — Clients must have Custom Shaders Patch installed
- **Content must be uploaded manually** — No automatic download mechanism
