# Fusion 360 on Fedora — GE-Proton + umu

> Autodesk Fusion 360 running on Fedora Linux: install it, fix the sign-in, fix the black canvas.

**Status: ✅ Working.** Fusion launches, Autodesk sign-in completes, the 3D canvas renders, and the RTX 3050 does the rendering.

This is an unofficial, documentation-first guide. It does not redistribute Autodesk software, GE-Proton, or UMU. Everything here was worked out on one real machine and is written so you can reproduce it.

---

## Contents

- [1. TL;DR](#1-tldr)
- [2. What works, and the two hard problems](#2-what-works-and-the-two-hard-problems)
- [3. The pieces (what each part does)](#3-the-pieces-what-each-part-does)
- [4. How this was reached (the story)](#4-how-this-was-reached-the-story)
- [5. Requirements](#5-requirements)
- [6. Setup, step by step](#6-setup-step-by-step)
- [7. Using it day to day](#7-using-it-day-to-day)
- [8. Troubleshooting](#8-troubleshooting)
- [9. Reference: files and paths](#9-reference-files-and-paths)
- [10. FAQ](#10-faq)
- [11. Legal](#11-legal)

---

## 1. TL;DR

The whole setup is three scripts. Install them and launch from the menu:

```bash
./scripts/install-local.sh          # installs the launchers + desktop entries
~/.local/bin/fusion360              # normal launch
```

The two things that make or break it:

1. **Sign-in** — the `adskidmgr://` callback must run **GE-Proton's bundled Wine binary directly** (not `umu-run`) against the same prefix. The repo's `fusion-adskidmgr-direct` script does this.
2. **Graphics** — **do not force the discrete GPU.** Do not export `__NV_PRIME_RENDER_OFFLOAD=1`, `__GLX_VENDOR_LIBRARY_NAME=nvidia` or `__VK_LAYER_NV_optimus=NVIDIA_only`. On hybrid Intel/NVIDIA they cause a black canvas (and a crash on cold boot). DXVK picks the RTX 3050 on its own.

If you remember only those two lines, you can skip the rest until something breaks.

---

## 2. What works, and the two hard problems

| Thing | State |
|---|---|
| Fusion installs into a dedicated prefix | ✅ |
| Fusion launches and reaches the workspace | ✅ |
| **Autodesk sign-in** (browser → `adskidmgr://` → app) | ✅ (see [§8.1](#81-sign-in-doesnt-complete)) |
| **3D canvas renders** | ✅ (see [§8.2](#82-black-3d-canvas)) |
| RTX 3050 used for rendering | ✅ (auto-selected by DXVK) |
| Fusion self-updates | ✅ (launcher auto-detects the new build — see [§8.4](#84-after-a-fusion-update)) |
| Native Wayland | ❌ (runs on XWayland — that is expected and fine) |
| Officially supported by Autodesk | ❌ (unofficial) |

Getting Fusion to *install and launch* was the easy part. The two hard problems — and the reason this guide exists — were:

1. **Authentication.** Chrome signed in fine, but Fusion stayed on the sign-in screen. The `adskidmgr://` callback was reaching the system but not completing the hand-off.
2. **Graphics.** Fusion came up with a **black 3D viewport**, and on a fresh boot could **die silently at Qt GUI init**.

Both are solved, and both have a single, specific cause. See [§4](#4-how-this-was-reached-the-story).

---

## 3. The pieces (what each part does)

```text
 Autodesk Fusion 360
        │
        ▼
 FusionLauncher.exe ───────────────┐
        │                          │
        ▼                          ▼
   umu-run                  GE-Proton's own wine
        │                     (sign-in callback only)
        ▼                          │
 Steam Linux Runtime 4             │
        │                          │
        ▼                          │
   GE-Proton 11-3  ◀───────────────┘
        │                    (both use the same prefix)
        ▼
 Dedicated Wine prefix
 ~/.local/share/fusion360/prefix
        │
        ├── Fusion360.exe  ──► DXVK ──► Vulkan ──► NVIDIA RTX 3050
        │                                        │
        │                                        ▼
        │                            XWayland → KWin (Intel) → panel
        │
        └── AdskIdentityManager.exe  (authentication)
```

| Piece | What it is | Why it's here |
|---|---|---|
| **GE-Proton 11-3** | A Proton (Wine) build with game/media patches | Runs Windows Fusion on Linux. Also ships the Wine binary the sign-in callback needs. |
| **umu-launcher** (`umu-run`) | A wrapper that runs any Windows app through Proton + the Steam Linux Runtime, outside Steam | Launches Fusion without adding it as a Steam game. |
| **Steam Linux Runtime 4** | Valve's container runtime providing the system libraries | umu fetches and manages it automatically. |
| **Dedicated Wine prefix** | A self-contained fake Windows filesystem | Keeps Fusion isolated from other Wine apps. Lives at `~/.local/share/fusion360/prefix`. |
| **FusionLauncher.exe** | Autodesk's small launcher | Sets up product/environment state before starting the app. Launch this, **not** `Fusion360.exe` directly. |
| **Fusion360.exe** | The actual application | Qt UI + D3D11 viewport. |
| **DXVK** | Translates Direct3D 9/10/11 to Vulkan | This is how the 3D viewport gets rendered on the NVIDIA GPU. |
| **AdskIdentityManager.exe** | Autodesk's SSO helper | Receives the browser callback and completes sign-in. |
| **`adskidmgr.desktop`** | KDE URI handler for `adskidmgr://` | Connects Chrome's callback to `fusion-adskidmgr-direct`. |

**The golden rule of this setup:** the main app goes through **umu + GE-Proton**, and the sign-in callback goes through **GE-Proton's Wine binary directly** — but both use the *same prefix*.

---

## 4. How this was reached (the story)

### Act 1 — Install and launch (straightforward)

Steam already worked. GE-Proton 11-3 was dropped into a Proton directory, umu-launcher was installed to `~/.local/bin/umu-run`, and the Autodesk `Fusion Client Downloader.exe` was run with `umu-run` into a dedicated prefix. Fusion installed. One wrinkle: the installed build was missing `FusionLauncher.exe.ini`, so the launcher complained — copying a valid `.ini` from an older build (whose `cmd=` pointed at the current `Fusion360.exe`) fixed it. ([§8.4](#84-after-a-fusion-update) covers this after future updates.)

Also cleaned up: an old **Bottles** Fusion install was still registered for `adskidmgr://` and was hijacking the callback. It was removed so there was only one URI handler.

### Act 2 — The sign-in wall

**Symptom:** Chrome completed the Autodesk login, the desktop asked *“Open Autodesk Identity Manager?”*, the callback was delivered as `adskidmgr:/login?...` — but Fusion stayed on the sign-in screen. Identity Manager logs said `Failed to refresh token. Not logged in.`

**Things that did *not* fix it:** `FUSION_IDSDK=false`, and the `bcp47langs=` override on its own.

**What fixed it:** changing *how* the callback was launched. Routing `adskidmgr://` through `umu-run` didn't complete the hand-off; launching `AdskIdentityManager.exe` with **GE-Proton's own `wine` binary**, against the same prefix, did:

```bash
# ✗ did not work
umu-run AdskIdentityManager.exe "adskidmgr:/login?..."

# ✓ works
"$PROTON/files/bin/wine" "$IDENTITY_MANAGER" "$@"
```

That single change made sign-in complete. ([§8.1](#81-sign-in-doesnt-complete))

### Act 3 — The black canvas (and the cold-boot crash)

**Symptom:** Fusion's UI drew, but the viewport where the model should be was **black**. Worse, on a **fresh boot** Fusion would sometimes **die silently at Qt GUI init** — no window, no error, no core dump, no OOM.

**Cause:** the launcher had been "helpfully" forcing the discrete GPU:

```bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
```

On this **hybrid** laptop the Intel iGPU drives the panel and KWin composites on Intel, while DXVK renders the canvas on NVIDIA and presents it through the Intel-composited XWayland surface. Forcing PRIME/NVIDIA GLX selection broke that cross-GPU hand-off → black canvas, and on cold boot a crash during Qt GUI init.

**What fixed it:** deleting all three variables. Fusion's log then went from stopping at `initializeGUI1 START / Set appUserModelId` (crash) to continuing through `initializeGUI1 END → initializeGUI2` (works), and the canvas rendered.

**And you lose nothing:** with no offload variables set, DXVK *still* selects the RTX 3050 — the log says `Creating device: ... Driver NVIDIA 615.71.9`.

Two more graphics invariants were confirmed along the way:

- **Launch `FusionLauncher.exe`, not `Fusion360.exe`** — the latter comes up with a black canvas.
- **Keep `QT_D3D_NO_FLIP=1`** — flip-model swapchains render black under DXVK.

### The result

```text
Fusion launches  →  sign-in completes  →  canvas renders  →  RTX 3050 accelerates  →  CAD is usable.
```

---

## 5. Requirements

- **Fedora 44** (KDE Plasma, Wayland session) — other recent Fedora/KDE versions should be similar.
- **Steam** installed and logged in (for the Steam Linux Runtime).
- **GE-Proton 11-3** (newer GE-Proton releases are worth trying).
- **umu-launcher 1.4.4+** → `~/.local/bin/umu-run`.
- An **NVIDIA GPU** (tested: RTX 3050 6 GB) on a hybrid Intel setup.
- The Autodesk **`Fusion Client Downloader.exe`** (Windows installer) in `~/Downloads`.
- ~10 GB free for the prefix. No root needed after the prerequisites.

### 5.1 Where to get each piece

| Piece | Where to get it |
|---|---|
| **Steam** | Your distro's package / [store.steampowered.com](https://store.steampowered.com/about/) — just install it and log in. |
| **GE-Proton 11-3** | [github.com/GloriousEggroll/proton-ge-custom/releases](https://github.com/GloriousEggroll/proton-ge-custom/releases) → download `GE-Proton11-3.tar.gz` and extract it (see [§6.1](#61-get-ge-proton-11-3)). |
| **umu-launcher** | [github.com/Open-Wine-Components/umu-launcher/releases](https://github.com/Open-Wine-Components/umu-launcher/releases) → either `pipx install umu-launcher` (puts `umu-run` in `~/.local/bin`) or grab the `.rpm`/zipapp from the releases page. See [§6.2](#62-install-umu-launcher). |
| **Autodesk Fusion installer** | Sign in / create an Autodesk account, then download from the Fusion product page ([autodesk.com/products/fusion-360/personal](https://www.autodesk.com/products/fusion-360/personal) — free for personal use). This gives you the **Windows** downloader, usually named **`Fusion Client Downloader.exe`**. See [§6.4](#64-get-and-install-fusion). |

> **About the installer:** you cannot install Fusion on Linux directly — there is no Linux build. You download Autodesk's **Windows** installer (the client downloader) and run *that* through umu + GE-Proton, which is exactly what [§6.4](#64-get-and-install-fusion) does.
>
> You will need an Autodesk account and a license (free **personal use**, a 30-day trial, or education). Sign in to the account once, "own" Fusion there, and the downloader appears under *Products and Services → Fusion → Download*. The file usually lands in `~/Downloads`. If yours has a different name, just adjust the path in the commands.

Tested hardware/versions:

| Component | Value |
|---|---|
| OS / kernel | Fedora 44 / `7.2.8-200.fc44.x86_64` |
| Session | KDE Plasma, Wayland |
| iGPU / dGPU | Intel Alder Lake-P UHD / NVIDIA RTX 3050 6 GB |
| NVIDIA driver | `615.71.09` |
| GE-Proton / DXVK | `11-3` / `3.0.2` (`v3.0.2-5-g1a5919b7e`) |
| umu-launcher | `1.4.4` |

---

## 6. Setup, step by step

> Run everything as your normal user. Do not use root.

### 6.1 Get GE-Proton 11-3

Download `GE-Proton11-3.tar.gz` from the
[GE-Proton 11-3 release](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton11-3)
and extract it where the launchers look for it:

```bash
mkdir -p ~/.local/share/fusion360/proton
tar -xzf ~/Downloads/GE-Proton11-3.tar.gz -C ~/.local/share/fusion360/proton
ls -d ~/.local/share/fusion360/proton/GE-Proton11-3     # must exist after this
```

The Steam compatibility-tools directory (`~/.steam/steam/compatibilitytools.d/GE-Proton11-3`) also works — the scripts auto-detect either.

### 6.2 Install umu-launcher

From the [umu-launcher releases](https://github.com/Open-Wine-Components/umu-launcher/releases), the simplest install is pipx:

```bash
pipx install umu-launcher          # drops umu-run in ~/.local/bin
# alternatives from the releases page: a Fedora .rpm, a .deb, or the zipapp

export PATH="$HOME/.local/bin:$PATH"
~/.local/bin/umu-run --version     # expect: umu-launcher version 1.4.4

# persist PATH in your shell
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

### 6.3 Create the dedicated prefix

```bash
mkdir -p ~/.local/share/fusion360/prefix
```

### 6.4 Get and install Fusion

There is no Linux build — download Autodesk's **Windows** installer:

1. Sign in / create an [Autodesk account](https://www.autodesk.com), get a license (free personal use / trial / education).
2. **Products and Services → Fusion → Download**. The Windows downloader lands in `~/Downloads` as (usually) `Fusion Client Downloader.exe`.

Then run that installer through umu + GE-Proton:

```bash
WINEPREFIX="$HOME/.local/share/fusion360/prefix" \
PROTONPATH="$HOME/.local/share/fusion360/proton/GE-Proton11-3" \
umu-run "$HOME/Downloads/Fusion Client Downloader.exe"
```

umu sets up Steam Linux Runtime 4 automatically. Fusion installs into:

```text
~/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production/<hash>/
```

### 6.5 Install the launchers

```bash
./scripts/install-local.sh
```

This installs:

```text
~/.local/bin/fusion360
~/.local/bin/fusion360-update
~/.local/bin/fusion-adskidmgr-direct
~/.local/share/applications/autodesk-fusion360.desktop
~/.local/share/applications/autodesk-fusion360-update.desktop
~/.local/share/applications/adskidmgr.desktop
```

…and registers the `adskidmgr://` URI handler. Verify it:

```bash
gio mime x-scheme-handler/adskidmgr
# expect: Default application for “x-scheme-handler/adskidmgr”: adskidmgr.desktop
```

### 6.6 Launch

```bash
~/.local/bin/fusion360
```

or pick **Autodesk Fusion 360** from the KDE application menu. Sign in when asked — Chrome will round-trip through `adskidmgr://` and Fusion should enter the workspace.

### 6.7 One-time checklist before you blame the guide

- [ ] `~/.local/bin/umu-run` exists and runs.
- [ ] GE-Proton 11-3 exists (dedicated dir **or** Steam compat dir).
- [ ] The prefix has a live `webdeploy/production/<hash>` with **both** `FusionLauncher.exe` and `Fusion360.exe`.
- [ ] `gio mime x-scheme-handler/adskidmgr` prints `adskidmgr.desktop`.
- [ ] Your launcher contains **no** `__NV_PRIME_RENDER_OFFLOAD` / `__GLX_VENDOR_LIBRARY_NAME=nvidia` / `__VK_LAYER_NV_optimus` lines.

---

## 7. Using it day to day

```bash
~/.local/bin/fusion360          # launch Fusion
~/.local/bin/fusion360-update   # run Autodesk's launcher to check for / apply updates
```

The launcher handles the rest: it finds the current build, refuses to start twice, and cleans up leftover Wine processes when you close Fusion (so the compatibility layer stops eating RAM).

---

## 8. Troubleshooting

### 8.1 Sign-in doesn't complete

**Symptom:** Chrome signs in, you get the *“Open Autodesk Identity Manager?”* prompt, but Fusion stays on the sign-in screen.

**The fix is almost always the callback path.** The `adskidmgr://` callback must run GE-Proton's Wine binary **directly**, with the **same prefix** — not through `umu-run`.

1. Check the URI handler points at our script:

   ```bash
   gio mime x-scheme-handler/adskidmgr
   cat ~/.local/share/applications/adskidmgr.desktop
   # Exec= should be .../fusion-adskidmgr-direct %u
   ```

2. Make sure no other handler (e.g. a leftover **Bottles** install) is also registered for `adskidmgr`. Remove it if so.

3. Confirm the callback script uses direct Wine:

   ```bash
   grep -n 'wine' ~/.local/bin/fusion-adskidmgr-direct
   # expect: exec "$WINE" "$IDENTITY_MANAGER" "$@"
   # NOT:    umu-run ...
   ```

4. Read the Identity Manager log:

   ```bash
   tail -200 "$HOME/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/Identity Services/Log/IdServices.log"
   ```

   Useful strings: `Failed to refresh token. Not logged in.`, `AdSSO server app does not found`.

> **Tip:** test one sign-in attempt at a time. Repeatedly firing the callback can pile up Identity Manager / WebView2 / Proton processes and eat all your RAM. Clean up with:
> ```bash
> pgrep -af 'umu-run|GE-Proton11-3|AdskIdentityManager|msedgewebview2|Fusion360|FusionLauncher'
> ```

### 8.2 Black 3D canvas

**Symptom:** The ribbon/browser/toolbars draw, but the 3D viewport is black.

**Cause:** force-discrete-GPU variables, or flip-model swapchains.

1. Make sure your launcher does **not** contain these (delete them if present):

   ```bash
   export __NV_PRIME_RENDER_OFFLOAD=1
   export __GLX_VENDOR_LIBRARY_NAME=nvidia
   export __VK_LAYER_NV_optimus=NVIDIA_only
   ```

2. Make sure `QT_D3D_NO_FLIP=1` **is** set.

3. Make sure you launch `FusionLauncher.exe`, not `Fusion360.exe`, and that you aren't running two copies.

4. Trace DXVK to see which GPU renders:

   ```bash
   DXVK_LOG_LEVEL=info ~/.local/bin/fusion360 2> ~/fusion-dxvk.log
   grep -iE 'Creating device|swapchain' ~/fusion-dxvk.log | head
   ```

   - `Creating device: ... Driver NVIDIA ...` → rendering is fine; the problem is present/compositing (offload vars, flip model, double launch).
   - `llvmpipe` / software → GPU selection itself is wrong.

> You will likely also see thousands of `Failed to open shared NT handle` warnings. That is a **known benign** DXVK 3.x + Wine 11.x issue (`doitsujin/dxvk#5771`) and is **not** the black-canvas cause.

### 8.3 Fusion won't start / dies silently (especially after a cold boot)

**Symptom:** No window, no error, no core dump; the app just exits during startup.

1. Confirm no force-discrete-GPU variables are set (see [§8.2](#82-black-3d-canvas)). This crash and the black canvas share the same cause.
2. Read the Neutron log and see where it stops:

   ```bash
   ls -t "$HOME/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/Neutron Platform/logs/" | head
   ```

   - Stops right after `Set appUserModelId` → the graphics/offload problem above.
   - Complains about `FusionLauncher.exe.ini` → see [§8.4](#84-after-a-fusion-update).
3. Try a clean launch:

   ```bash
   pkill -f 'Fusion360.exe|FusionLauncher.exe' || true
   pkill -f 'GE-Proton11-3|umu-run' || true
   ~/.local/bin/fusion360
   ```

### 8.4 After a Fusion update

Fusion self-updates by installing into a **new** `webdeploy/production/<hash>` directory and retiring the old one. **You normally don't have to do anything** — the launcher detects the newest folder that contains both `FusionLauncher.exe` and `Fusion360.exe`.

If something looks wrong after an update:

1. **Run the launcher to apply the update** (rather than letting the app update itself mid-session):

   ```bash
   ~/.local/bin/fusion360-update
   ```

2. **See what deployments exist:**

   ```bash
   for d in "$HOME/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production"/*/; do
       printf '%s  F360=%s LAUNCH=%s\n' "$(basename "$d")" \
           "$([ -f "$d/Fusion360.exe" ] && echo y || echo n)" \
           "$([ -f "$d/FusionLauncher.exe" ] && echo y || echo n)"
   done
   ```

   The live build has `F360=y LAUNCH=y`. Old entries with `LAUNCH=y F360=n` are stale and ignored.

3. **If the launcher says “Configuration file FusionLauncher.exe.ini is missing or incomplete”**, copy a valid `.ini` from another deployment:

   ```bash
   DEPLOY="$HOME/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production"
   cp "$DEPLOY/<old-hash>/FusionLauncher.exe.ini" "$DEPLOY/<new-hash>/FusionLauncher.exe.ini"
   ```

   (The `.ini` just needs its `cmd =` line to point at the current `Fusion360.exe`.)

### 8.5 “Fusion 360 is already running” but I can't see it

The launchers refuse to start while another instance is alive, because **two `umu-run` instances on one prefix fight over the Wine lock and give you a black canvas plus heavy thrash.**

```bash
pgrep -af 'FusionLauncher.exe|Fusion360.exe'    # look for leftovers
pkill -f 'Fusion360.exe' || true
pkill -f 'FusionLauncher.exe' || true
```

### 8.6 Leftover windows after Alt-Tab

Under KDE Wayland, some Fusion child panels can stay on top and remain clickable after you switch away. **Partial fix:** KWin window rules (`~/.config/kwinrulesrc`) that keep Fusion's dialogs tied to the main window reduce it, but don't fully remove it. It's cosmetic and unrelated to sign-in or rendering.

### 8.7 Is Fusion really using the RTX 3050?

```bash
nvidia-smi
```

Expect `Fusion360.exe` to hold roughly 1.5–1.7 GB of VRAM while open (and `msedgewebview2.exe` a small amount). A momentary `0%` utilization reading is **not** evidence of missing acceleration — VRAM allocation and process presence are the useful signals. When in doubt, the DXVK log's `Creating device: ... NVIDIA ...` is the authoritative answer.

### 8.8 Nuclear cleanup / backup

**Back up the prefix** before any destructive testing:

```bash
tar -C "$HOME/.local/share" -czf "$HOME/fusion360-prefix-backup.tar.gz" fusion360/prefix
```

**Stop a stuck session:**

```bash
pkill -f "$HOME/.local/share/fusion360/prefix.*Fusion360.exe" || true
pkill -f "$HOME/.local/share/fusion360/prefix.*FusionLauncher.exe" || true
pkill -f "$HOME/.local/share/fusion360/prefix.*AdskIdentityManager.exe" || true
pgrep -af 'fusion360/prefix.*(Fusion360|FusionLauncher|AdskIdentityManager)' || echo "Fusion clean"
```

Don't delete the prefix casually — it holds the app, Identity Manager state, WebView2 state and config.

---

## 9. Reference: files and paths

```text
Fusion prefix:            ~/.local/share/fusion360/prefix
GE-Proton (tested):       ~/.local/share/fusion360/proton/GE-Proton11-3
GE-Proton (alternative):  ~/.steam/steam/compatibilitytools.d/GE-Proton11-3
umu:                      ~/.local/bin/umu-run

Fusion launcher:          ~/.local/bin/fusion360
Updater launcher:         ~/.local/bin/fusion360-update
Sign-in callback handler: ~/.local/bin/fusion-adskidmgr-direct

KDE app entry:            ~/.local/share/applications/autodesk-fusion360.desktop
KDE app entry (update):   ~/.local/share/applications/autodesk-fusion360-update.desktop
URI handler:              ~/.local/share/applications/adskidmgr.desktop

Live deployment:          .../webdeploy/production/<hash>/   (auto-detected)
```

Useful process check:

```bash
pgrep -af 'umu-run|GE-Proton11-3|AdskIdentityManager|FusionLauncher|Fusion360|msedgewebview2'
```

---

## 10. FAQ

**Do I have to force the NVIDIA GPU?** No. DXVK selects it automatically. Forcing it breaks the canvas on hybrid graphics.

**Why does sign-in need a different launch method than the app?** Because the `adskidmgr://` callback is a separate, short-lived process that must talk to the same Wine prefix. On the tested setup, only direct invocation with GE-Proton's Wine binary completed the hand-off.

**Can I run it under X11 instead of Wayland?** Untested here, but a reasonable experiment if the Alt-Tab window issue annoys you — the prefix, Proton and scripts would be unchanged.

**Will a Fusion update break this?** Normally no — the launcher auto-detects the new build. If the `.ini` is missing, copy it ([§8.4](#84-after-a-fusion-update)).

**Is this supported by Autodesk?** No. It's an unofficial Wine/Proton configuration.

**Something is eating all my RAM after testing auth repeatedly.** Kill the leftovers — see [§8.8](#88-nuclear-cleanup--backup).

---

## 11. Legal

This repository contains documentation and user-created launcher scripts only. It does not distribute Autodesk Fusion 360, Autodesk binaries, Microsoft runtime files, or GE-Proton. Autodesk software remains subject to Autodesk's licensing and terms. Use at your own risk.
