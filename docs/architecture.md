# Runtime Architecture

## Main application path

```text
KDE application launcher / shell
          |
          v
~/.local/bin/fusion360
          |
          v
umu-run
          |
          v
Steam Linux Runtime 4
          |
          v
GE-Proton 11-3
          |
          v
FusionLauncher.exe        <- launch the launcher, not Fusion360.exe
          |
          v
Fusion360.exe
```

Autodesk installs each build into `webdeploy/production/<hash>` and a
self-update replaces that directory, while keeping a persistent launcher
directory for shortcut references. The launcher script detects the newest folder
that contains both `FusionLauncher.exe` and `Fusion360.exe` instead of
hard-coding a hash.

## What the launcher does

`~/.local/bin/fusion360`:

1. Resolves GE-Proton (dedicated Fusion tree or Steam compatibility-tools dir).
2. Resolves the live Fusion deployment by mtime.
3. Ensures `FusionLauncher.exe.ini` exists in that deployment folder (dynamically
   writing the UTF-16LE configuration if missing, preventing the post-update
   "Configuration file is missing or incomplete" error).
4. Refuses to start a second instance while Fusion is running (double-launch
   causes a black canvas and Wine-lock thrash).
5. Exports `WINEPREFIX`, `PROTONPATH`, `QT_D3D_NO_FLIP=1`,
   `WINEDLLOVERRIDES="bcp47langs=,icuuc=n"` and quiet DXVK/VKD3D logging.
6. Deliberately does **not** export any force-discrete-GPU variables.
7. Runs `FusionLauncher.exe` via UMU, then cleans up leftover Proton/Wine
   processes when `Fusion360.exe` exits.

## Rendering / present path

```text
Fusion360.exe (Qt RHI = Direct3D11)
          |
          v
      DXVK (d3d11 -> Vulkan)
          |
          v
Vulkan device selected by DXVK
 (auto: NVIDIA RTX 3050)
          |
          v
XWayland surface (Fusion windows are X11)
          |
          v
KWin compositor on the Intel iGPU
          |
          v
eDP-1 panel
```

The canvas is rendered on the NVIDIA GPU and composited by KWin on the Intel
iGPU. Forcing `__NV_PRIME_RENDER_OFFLOAD` / `__GLX_VENDOR_LIBRARY_NAME=nvidia` /
`__VK_LAYER_NV_optimus=NVIDIA_only` breaks this cross-GPU present, producing a
black viewport (and, on a cold boot, a crash at Qt GUI init). See
`docs/graphics.md`.

## Authentication callback path

```text
Chromium / Autodesk login
          |
          | adskidmgr://
          v
KDE x-scheme-handler/adskidmgr
          |
          v
~/.local/bin/fusion-adskidmgr-direct
          |
          v
GE-Proton11-3/files/bin/wine
          |
          v
AdskIdentityManager.exe
          |
          v
~/.local/share/fusion360/prefix
          |
          v
Fusion IPC / authenticated session
```

## Why two paths?

UMU provides the Steam runtime environment used by the main Windows application. The browser callback is a separate external-protocol invocation. In the tested configuration, invoking Identity Manager through UMU did not complete the authentication handoff, while direct invocation through GE-Proton's Wine executable did.

The practical rule is therefore:

- use **UMU for Fusion**
- use **GE-Proton's Wine binary directly for `adskidmgr://`**
- use the **same prefix for both**

## Files

```text
~/.local/bin/fusion360
~/.local/bin/fusion360-update
~/.local/bin/fusion-adskidmgr-direct
~/.local/share/applications/autodesk-fusion360.desktop
~/.local/share/applications/autodesk-fusion360-update.desktop
~/.local/share/applications/adskidmgr.desktop
~/.local/share/fusion360/prefix
~/.local/share/fusion360/proton/GE-Proton11-3
```

## Verification

Check the runner:

```bash
ls -d ~/.local/share/fusion360/proton/GE-Proton11-3 \
      ~/.steam/steam/compatibilitytools.d/GE-Proton11-3 2>/dev/null
```

Check UMU:

```bash
~/.local/bin/umu-run --version
```

Check Fusion processes:

```bash
pgrep -af 'Fusion360|FusionLauncher|AdskIdentityManager'
```

Check NVIDIA use:

```bash
nvidia-smi
```
