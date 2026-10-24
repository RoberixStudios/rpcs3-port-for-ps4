# RPCS3 PORT FOR PS4 0.40 - source code

**RPCS3 PORT FOR PS4** is a port of [RPCS3](https://rpcs3.net), the PlayStation 3 emulator, to
PlayStation 4 consoles running the GoldHEN homebrew enabler.

> **Unofficial project.** It is not affiliated with Sony Interactive Entertainment or the RPCS3 team.
> Please do not ask the RPCS3 team for support with this port.

The emulation core is the original RPCS3 code (upstream commit
`9d52b338058bda2d5a9d7cd5e4fbc8148e55a385`), cross-compiled for the PS4 with the OpenOrbis PS4
Toolchain. The port adds the console frontend, native adapters for memory, video, audio, controllers,
network and USB, and an XMB-style launcher.

This folder holds the source code of version 0.40, released under the GNU General Public
License version 2 (see [`LICENSE`](LICENSE)).

## What is in this folder

| Path | Contents |
| --- | --- |
| `rpcs3-ps4/` | The repository: the RPCS3 tree (`rpcs3/`, `Utilities/`, `3rdparty/`, `bin/`, `buildfiles/`, CMake files) with the port's changes, plus the port itself in `rpcs3-ps4/ps4-port/` |
| `rpcs3-ps4/ps4-port/` | Cross-build (toolchain, dependencies, native link), dependency and packaging scripts, PS4 runtime code, host tests, user guides |
| `rpcs3-ps4/rpcs3/ps4_*.cpp`, `rpcs3-ps4/rpcs3/util/ps4_*.hpp` | Console frontend, XMB launcher, settings, memory budget, RPCN, system health and other port code |
| `orbis-compat/` | The orbis-compat sources the build compiles (POSIX/libkernel compatibility runtime for the PS4), with the port's changes |
| [`BUILDING.md`](BUILDING.md) | How to build the ELF and the PKG |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | Every bundled component and its license |
| `licenses/` | License texts of components that are built or packaged but whose sources are not in this folder |

`rpcs3-ps4/` and `orbis-compat/` must stay side by side: the build finds `orbis-compat` at
`rpcs3-ps4/../orbis-compat` by default.

## Status

This is an experimental pre-release. On the 0.39 console tests several games reached their menus but not
stable gameplay, mostly because the console ran out of threads; 0.40 targets that problem and still needs
console tests. Compatibility and speed vary a lot from game to game.

What is new in 0.40:

- More thread headroom for games (idle emulator threads are never started, the last thread slots are kept
  for the game) and an automatic per-game safe mode that turns features off step by step after a failure.
- Changes from 0.39 that affect every game are off by default and can be turned on one by one for testing
  (`/data/rpcs3/features.txt`).
- Graphics fixes (objects hidden while their shaders compile), audio after pauses, settings applied as the
  player chose them (console limits are shown with their reason).
- Physical discs and encrypted ISOs without internet once their key is known or supplied by the user
  (`/data/rpcs3/keys` or a `keys` folder on a USB drive). No keys are included.
- XMB: the selected game's own background picture and music (from the game's files), folders to
  organize games, and a new application icon.

## Features

- The RPCS3 PPU and SPU LLVM recompilers running on the PS4 itself (LLVM pinned by RPCS3's own
  submodule), plus SPU ASMJIT and the interpreters.
- Vulkan through the Mesa RADV driver (the original `VKGSRender`), and OpenGL through Mesa EGL and
  Zink over RADV (the original `GLGSRender`).
- Automatic configuration: a PS4 profile and the known fixes of each title are applied when a game
  starts; after a failure the next start adapts by itself. Per-game settings remain possible.
- Up to 4 players, one DualShock 4 per signed-in PS4 user.
- Online play through RPCN (RPCS3's own server): experimental; keep PlayStation Network > Online mode
  off unless you have an RPCN account.
- XMB launcher: game list (folders, ISO, PKG), PS3 PKG installation (games, updates, DLC), `.rap`
  license import, global and per-game settings, patches and cheats, PS3 discs read from the PS4 drive.
- Return from a game to the XMB without closing the application (L1 + R1 + Triangle for 1 second, or
  L1 + R1 + Options for 2 seconds).

The user guide (in Portuguese) is [`rpcs3-ps4/ps4-port/TUTORIAL.txt`](rpcs3-ps4/ps4-port/TUTORIAL.txt),
and the console test guide is [`rpcs3-ps4/ps4-port/TESTAR_NO_PS4.txt`](rpcs3-ps4/ps4-port/TESTAR_NO_PS4.txt).
Both are also inside the PKG.

## Requirements

- A PS4 or PS4 Pro with **GoldHEN** (on a PS4 Pro, turn on Boost Mode in the system settings).
- The official PS3 system software (`PS3UPDAT.PUP`), installed from the XMB (see below).
- Your own PS3 games (disc folder, ISO or PKG). The package contains no games, firmware, keys or
  licenses.

The PS4's Jaguar CPU is much slower than a PC's, so many games run below full speed. The first start of each game compiles its code ("Compiling PPU Modules" / "Building SPU Cache")
and can take many minutes; later starts use the cache.

## Installing the PKG

1. Copy the `.pkg` to `/data/pkg` on the console and install it with GoldHEN
   (Debug Settings > Package Installer). Installing a newer package keeps the settings and caches.
2. Put `PS3UPDAT.PUP` on a USB drive (in `PS3/UPDATE/` or the root) and use
   XMB > Settings > Install PS3 firmware. It is installed to `/data/rpcs3/dev_flash`.
3. Put your games in one of these places:
   - `/data/rpcs3/games/NAME` (with `PS3_GAME/USRDIR/EBOOT.BIN`), or an ISO in `/data/rpcs3/games`;
   - PS3 PKG files in `/data/rpcs3/pkgs`;
   - on a USB drive: `PS3`, `GAMES`, `PS3ISO` or `PKG`;
   - `.rap` licenses in `/data/rpcs3/raps` (or next to the PKG files);
   - or insert a PS3 disc in the PS4 drive (with GoldHEN's FTP server on) and choose "PS3 disc"
     ("Disco de PS3" in Portuguese) in the list to install it.
4. Start **RPCS3 PORT FOR PS4** from the home screen (title ID `RPCS30010`).

## Download and reporting problems

- The PKG of each version is on the [Releases](https://github.com/RoberixStudios/rpcs3-port-for-ps4/releases)
  page, with its SHA-256.
- To report a problem, open an [issue](https://github.com/RoberixStudios/rpcs3-port-for-ps4/issues) and attach
  `/data/rpcs3/startup.log`, `/data/rpcs3/log/RPCS3.log` and `/data/rpcs3/log/mesa.log` (copy them with
  GoldHEN's FTP server). The logs can contain your PS4 user names.

## Building

The build runs on a Windows host and produces the native ELF, the EBOOT and the PKG. In short:
OpenOrbis PS4 Toolchain + llvm-mingw, the Mesa PS4 bundle and orbis-porting-kit next to this folder,
the dependency scripts in `ps4-port/`, one CMake/Ninja target (`rpcs3_ps4_elf`) and
`ps4-port/package-native.ps1`. Every step is in [`BUILDING.md`](BUILDING.md).

## Credits

- **RPCS3**: the whole emulation core, the renderers, the recompilers and the interface icons are the
  work of the RPCS3 team and its contributors (https://rpcs3.net, https://github.com/RPCS3/rpcs3),
  licensed under GPL-2.0. This port is distributed under the same license.
- **PS4 port**: Roberix Studio (also the application icon, the studio logo).
- **orbis-compat** and **orbis-porting-kit** (orbis-ports, by Mikołaj Mikołajczyk, MIT): the PS4
  compatibility runtime and the Vulkan loader the port is built on.
- **OpenOrbis PS4 Toolchain**: the SDK, the C/C++ runtime and the packaging tools.
- **Mesa** (RADV, EGL, Gallium/Zink), **LLVM**, **FFmpeg**, **wolfSSL**, **curl** and the other
  components listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- **GoldHEN**, which makes homebrew such as this possible on the console.

## License

The port and the RPCS3 code are licensed under the GNU General Public License, version 2
([`LICENSE`](LICENSE), the same text as `rpcs3-ps4/LICENSE`). Third-party components keep their own
licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Disclaimer

This is an unofficial project. It is not affiliated with, endorsed by or sponsored by Sony
Interactive Entertainment or the RPCS3 team. "PlayStation", "PS3" and "PS4" are trademarks of Sony
Interactive Entertainment Inc. No games, system software, keys or licenses are included or
distributed: use only copies of games you own.
