# Autodesk Fusion on Linux

> Unofficial, reproducible setup to run **Autodesk Fusion 360** on Linux using GE-Proton + umu-launcher. This repo documents the configuration that worked on the tested hardware, along with the fixes for the two hard parts: the `adskidmgr://` sign-in callback and the 3D viewport on hybrid graphics.

## TL;DR

- **What works:** Fusion 360 install, sign-in (via direct-Wine callback), 3D viewport rendering, and updates on the tested system.
- **Not affiliated with Autodesk.** No redistribution of Autodesk binaries, GE-Proton, or UMU; no OAuth material.
- **Status:** Experimental. Treat "tested on this machine" as the verified scope (see Compatibility Matrix).

### Tested configuration

| Component | Details |
|---|---|
| Distribution | Fedora 44 |
| Desktop/Session | KDE Plasma on Wayland |
| CPU/GPU | Intel Alder Lake-P + NVIDIA RTX 3050 Laptop GPU (hybrid) |
| NVIDIA Driver | 615.71.09 |
| GE-Proton | 11-3 |
| DXVK | v3.0.2-5-g1a5919b7e |
| umu-launcher | 1.4.4 |

### Limitations

- **Unofficial.** Autodesk does not officially support Linux.
- **Hardware-specific.** This is a working configuration on one hybrid laptop; results vary by GPU, driver, compositor, and session.
- **Experimental.** Use at your own risk.

## Quick Start

### Prerequisites

- A valid Autodesk account with access to Fusion 360
- [GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom/releases) (tested: 11-3). Place in `~/.local/share/fusion360/proton/GE-Proton11-3/` or in a Steam compatibility tools directory.
- [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) (e.g. `pipx install umu-launcher` or your distro package).
- Fusion 360 installer downloaded from Autodesk (Products and Services → Fusion → Download). This repo does **not** include it.
- `wine`, `curl`, `unzip`, `wget`, `desktop-file-utils` available in your environment.

### Installation

```bash
# Clone this repo
git clone https://github.com/Rujul-Rumale/autodesk-fusion-fedora-geproton.git
cd autodesk-fusion-fedora-geproton

# Install launchers + .desktop files to ~/.local
./scripts/install-local.sh
```

The installer copies the launcher scripts to `~/.local/bin/` and creates three `.desktop` entries in `~/.local/share/applications/`.

### Launching

1. Run **Autodesk Fusion 360** from your application launcher (or `fusion360` in a terminal).
2. The first run sets up the Wine prefix and launches the Fusion deployment.
3. For the Autodesk sign-in callback (`adskidmgr://...`), the included handler routes it through GE-Proton's bundled Wine directly (never via `umu-run`). This is handled automatically by the provided scripts.

See [docs/installation.md](docs/installation.md) for details.

## Compatibility Matrix

| Configuration | Status | Notes |
|---|---|---|
| Tested: Fedora 44, KDE Plasma (Wayland), Intel Alder Lake-P + NVIDIA RTX 3050 Laptop GPU | **Verified** | Working as documented on this machine. |
| Other Fedora releases | **Untested** | May work; please report your results. |
| Other distributions (Ubuntu/Debian/Arch/openSUSE etc.) | **Untested** | Approach is general, but paths/env may differ. |
| AMD-only GPUs | **Untested** | No data yet. |
| Intel-only GPUs | **Untested** | No data yet. |
| Other NVIDIA GPUs (desktop/laptop) | **Untested** | Behavior varies by driver/compositor. |
| GNOME (Wayland/X11) | **Untested** | May behave differently than KDE. |
| Other Wayland compositors | **Untested** | Needs verification. |
| X11 sessions | **Untested** | Needs verification. |

## Known Issues & Workarounds

### 1) Autodesk sign-in (`adskidmgr://` callback)

On some Linux/Wine setups, the identity manager callback can get stuck. The provided `fusion-adskidmgr-direct` script launches `AdskIdentityManager.exe` directly with GE-Proton's bundled Wine (not `umu-run`), which matches the working path on this system.

See [docs/authentication.md](docs/authentication.md) for details.

### 2) Black 3D viewport / cold-boot startup failure (hybrid GPU)

On the tested Intel/NVIDIA hybrid laptop, **removing** the explicit GPU-forcing environment variables (`__NV_PRIME_RENDER_OFFLOAD`, `__GLX_VENDOR_LIBRARY_NAME`, `__VK_LAYER_NV_optimus`) resolved both the black viewport and the cold-boot GUI-init crash.

> Note: On the tested configuration, DXVK continued to select the NVIDIA GPU in the working setup. This is an **observed correlation and successful workaround**, not a universal statement about all hybrid-GPU systems. Compositors, drivers, and sessions can differ.

See [docs/graphics.md](docs/graphics.md) for logs and context.

## Quick Troubleshooting

Common fixes are documented in [docs/troubleshooting.md](docs/troubleshooting.md), covering:

- Fusion fails to start / double-launch guard
- Black canvas persists
- Sign-in stuck on callback
- Updates / deployment selection
- Cleanup on crashes

## Contributing

Contributions are welcome, especially compatibility reports from untested configurations. When reporting issues:

1. **Use a clear title** describing the problem (sign-in, graphics, install, etc.)
2. **Include system details** (distro/kernel/desktop/session, GPUs + driver, GE-Proton, umu-launcher, DXVK/Wine versions)
3. **Describe reproduction** (fresh launch, sign-in, viewport, relaunch, updater)
4. **Attach relevant logs** (terminal output, `dxvk.log` if available). Do **not** attach authentication URLs, tokens, cookies, or any account identifiers.
5. **Respect privacy**: redact anything sensitive before posting.

### Bug Report Template

```markdown
## System
- Distribution and version:
- Kernel:
- Desktop / session (Wayland/X11):
- GPU(s) and driver:
- GE-Proton version:
- umu-launcher version:
- DXVK/Wine version (if known):

## Test results
- Installation completed: [yes/no]
- Autodesk sign-in completed: [yes/no]
- 3D viewport renders: [yes/no]
- GPU acceleration observed: [yes/no]
- Restart / cold-boot behaviour: [works/fails]

## Failure
- Expected behaviour:
- Actual behaviour:
- Steps to reproduce:

## Logs & notes
- Relevant logs (redact sensitive info):
- Additional context:

## Privacy check
Authentication URLs, tokens, and personal account information have been removed: [yes]
```

### Release Verification Checklist

Before tagging a release or promoting script changes:

- [ ] Fresh install via `install-local.sh` on a clean environment (or prefix reset path tested)
- [ ] Launch Fusion 360 successfully
- [ ] Sign in completes (adskidmgr callback works)
- [ ] 3D viewport renders correctly
- [ ] Basic CAD interaction works
- [ ] Close Fusion cleanly (no stray processes)
- [ ] Relaunch works (double-launch guard behaves correctly)
- [ ] Update path (`fusion360-update`) works
- [ ] Scripts pass `bash -n` and basic sanity checks

## How This Was Reached

The technical journey (debugging steps, logs, and what led to the fixes) is documented in [Fusion360_Fedora44_GE-Proton_Workflow.md](Fusion360_Fedora44_GE-Proton_Workflow.md). For architecture details, see [docs/architecture.md](docs/architecture.md).

## Disclaimer

This is an unofficial community project. It is not endorsed, supported, or affiliated with Autodesk Inc. Use at your own risk.
