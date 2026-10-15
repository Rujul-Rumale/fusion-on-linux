# Troubleshooting and Experiments

This file records the major experiments from the working session. The purpose is to preserve the reasoning, not to recommend every attempted path.

## 1. Existing Bottles setup

An older Bottles-based Fusion environment existed on the system. Its Autodesk URI handler pointed to the Bottles Fusion prefix and repeatedly produced the Bottles bottle-selection interface after Chrome requested `adskidmgr://`.

The Bottles installation was removed once the dedicated Proton environment was working well enough to diagnose independently.

The lesson was to avoid having two competing `adskidmgr://` implementations during authentication debugging.

## 2. ProtonUp-Qt / DNF

Fedora's configured repositories did not provide `protonup-qt` or `umu-launcher`.

We therefore installed GE-Proton manually (into a dedicated Fusion directory or
the Steam compatibility-tools directory) and installed UMU manually under
`~/.local/bin`.

## 3. Steam Runtime 4

UMU initially reported:

```text
steamrt4 validation failed
Could not find steamrt4_platform_* ...
```

It then downloaded and verified Steam Linux Runtime 4 automatically. Subsequent launches reported the runtime as up to date.

## 4. FusionLauncher.exe.ini

The initial installed deployment contained `FusionLauncher.exe` but no `FusionLauncher.exe.ini`.

Launching the launcher produced the Autodesk error that the configuration file was missing/incomplete.

An older production directory contained a valid `.ini` pointing to the current `Fusion360.exe`. Copying that file into the current production directory repaired the launcher.

## 5. Identity Manager / AdSSO investigation

The current Fusion deployment contained:

```text
AdskIdentityManager.exe
AdSSOServices.dll
SSOClient.config
SSOPlugin/Current/IdSDKPlugin.dll
```

but no `AdSSO.exe` was found anywhere in the prefix.

`SSOClient.config` explicitly referenced:

```text
AdSSO.exe
Autodesk.SSO.DefaultProcess-v2
Autodesk.SSO.DefaultServer-v2
```

The Identity Manager log repeatedly reported:

```text
AdSSO server app does not found
```

However, later logs established that `AdskIdentityManager.exe` itself successfully became the SSO server and Fusion connected to it. Therefore the missing `AdSSO.exe` string alone was not enough to explain the complete failure.

## 6. `FUSION_IDSDK=false`

Tested as a historical Fusion/Wine workaround.

Result on the tested current Fusion build: ineffective. The Identity SDK remained active and Identity Manager still handled login.

It is not part of the final configuration.

## 7. `bcp47langs` and `icuuc` overrides

Tested:

```bash
export WINEDLLOVERRIDES="bcp47langs="
```

It did not resolve authentication by itself.

The final launcher uses both overrides:

```bash
export WINEDLLOVERRIDES="bcp47langs=,icuuc=n"
```

`bcp47langs=` is a long-standing Fusion/Wine compatibility override.
`icuuc=n` disables Wine's ICU shim, which otherwise interferes with the
.NET/CLR runtime bits Fusion loads.

## 8. Final authentication fix

The decisive A/B test was changing the callback handler from `umu-run` to GE-Proton's own Wine executable.

Failing conceptual callback:

```text
adskidmgr://
    ↓
umu-run
    ↓
AdskIdentityManager.exe
```

Working callback:

```text
adskidmgr://
    ↓
GE-Proton/files/bin/wine
    ↓
AdskIdentityManager.exe
```

Both use the same Fusion prefix.

## 9. Resource exhaustion incident

Repeatedly launching Identity Manager during authentication debugging caused multiple UMU/Proton/Identity Manager/WebView2 processes to accumulate. CPU and RAM reached approximately 100%, and the laptop became unusably slow.

A reboot cleared the processes.

Preventive rule:

> When testing authentication, perform one controlled launch at a time. Do not repeatedly spawn Identity Manager manually.

Useful cleanup check:

```bash
pgrep -af 'umu-run|GE-Proton11-3|AdskIdentityManager|msedgewebview2|Fusion360|FusionLauncher'
```

## 10. Wayland / Alt-Tab issue

After the core installation was working, a separate UI issue was observed under KDE Wayland: after Alt-Tabbing away from Fusion, some Fusion child UI panels could remain visible on top of other applications, and those panels could remain interactive.

This is separate from authentication and was intentionally not modified during the successful installation work.

**Partial mitigation:** KWin window rules (`~/.config/kwinrulesrc`) that keep
Fusion's child dialogs associated with, and focused alongside, the main Fusion
window reduce (but do not fully eliminate) the problem.

A future A/B experiment is to test the identical Fusion installation under KDE Plasma X11, without changing Proton or the prefix.

## 11. Black 3D canvas

Symptom: Fusion's UI (ribbon, browser, toolbars) draws, but the viewport where
the model should be is black.

**Cause found:** the launcher was exporting the force-discrete-GPU variables.

```bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
```

On this hybrid Intel + NVIDIA setup they broke the cross-GPU present path.

**Fix:** remove all three. DXVK selects the NVIDIA GPU on its own
(`Creating device: ... Driver NVIDIA ...`), so no GPU acceleration is lost.

Keep `QT_D3D_NO_FLIP=1`: flip-model swapchains render black under DXVK.

Do not pass `--disable-gpu` — it also removes the canvas.

See `docs/graphics.md` for the full explanation and diagnostic recipe.

## 12. Silent crash at Qt GUI init on a fresh boot

Symptom: on a cold boot, Fusion dies during startup with no window, no error
dialog, no core dump, and no OOM.

The Neutron `AppLogFile` for such a session stops right at:

```text
PERF: initializeGUI1 START.
Set appUserModelId from config: AutodeskInc.Fusion360
```

whereas a working session continues to `initializeGUI1 END` and
`initializeGUI2 ...`.

**Same cause as §11.** Removing the three force-discrete-GPU variables let GUI
init complete on the next launch.

Note: because the crash only appeared on a *fresh boot*, an already-running
session can mask the problem. If Fusion runs after a warm restart but crashes
from a cold boot, suspect the offload variables.

## 13. Double launch causes a black canvas

Starting a second `umu-run` while Fusion is already up makes the two instances
fight over the Wine lock. The observed result was a black canvas plus heavy
CPU/disk thrash.

The launchers guard against it:

```bash
if pgrep -f 'FusionLauncher.exe' >/dev/null 2>&1 || pgrep -f 'Fusion360.exe' >/dev/null 2>&1; then
    echo "Fusion 360 is already running." >&2
    exit 0
fi
```

If you are sure nothing is running but the guard trips, check for stale
processes:

```bash
pgrep -af 'FusionLauncher.exe|Fusion360.exe'
```

## 14. Benign DXVK log spam: `Failed to open shared NT handle`

A DXVK session can emit thousands of lines like:

```text
warn: DxgiSwapChain::CreateSwapChain: Failed to open shared NT handle ...
```

This is a known DXVK 3.x + Wine 11.x issue (upstream `doitsujin/dxvk#5771`). It
also appears on fully working systems and is **not** a fault in this setup.
Running with `DXVK_LOG_LEVEL=none` (the launcher default) suppresses it.

## 15. Updating Fusion

Fusion self-updates, which replaces the `webdeploy/production/<hash>` directory.
Because the launcher auto-detects the live deployment, no path edit is needed
after an update. If an update leaves a launcher without its `.ini`, see §4.

To trigger an update check / reinstall, use `scripts/fusion360-update`, which
runs the Autodesk launcher without waiting on the main application.

## 16. Recovery / reset notes

Do not delete the Fusion prefix casually; it holds the installed application,
Identity Manager state, WebView2 state, and configuration.

Backup:

```bash
tar -C "$HOME/.local/share" -czf "$HOME/fusion360-prefix-backup.tar.gz" fusion360/prefix
```

Stop a stuck session:

```bash
pkill -f "$HOME/.local/share/fusion360/prefix.*Fusion360.exe" || true
pkill -f "$HOME/.local/share/fusion360/prefix.*FusionLauncher.exe" || true
pkill -f "$HOME/.local/share/fusion360/prefix.*AdskIdentityManager.exe" || true
```

Verify clean:

```bash
pgrep -af 'fusion360/prefix.*(Fusion360|FusionLauncher|AdskIdentityManager)' || echo "Fusion clean"
```
