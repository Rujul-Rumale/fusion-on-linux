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

## 4. FusionLauncher.exe.ini & Launcher Architecture

### The symptom
Launching the launcher produces an Autodesk error dialog:

```text
Configuration file '%1' is missing or incomplete.
Please re-install the application, and contact support if this does not resolve the probem.
```

### Root cause
Autodesk WebDeploy uses a split directory layout under `webdeploy/production/`:
1. **Persistent launcher directory** (e.g. `6a0c9611291d45bb9226980209917c3d`):
   * This is where Autodesk creates the Windows Desktop / Start Menu shortcut (`Autodesk Fusion.lnk`).
   * Contains `FusionLauncher.exe` and `FusionLauncher.exe.ini`.
   * Its `FusionLauncher.exe.ini` contains:
     ```ini
     [Launcher]
     stream = production
     auid = AutodeskInc.Fusion360
     cmd = ""C:\users\steamuser\AppData\Local\Autodesk\webdeploy\production\<payload_hash>\Fusion360.exe""
     global = False
     ```
2. **Versioned payload directories** (e.g. `a3178fba...`):
   * Contains the full application binaries (`Fusion360.exe`, DLLs, runtime files) and a copy of `FusionLauncher.exe`.
   * **Crucially, Autodesk does not place a `FusionLauncher.exe.ini` inside this payload directory.**

Because the Linux wrapper script (`scripts/fusion360`) dynamically targets the payload directory that contains `Fusion360.exe` as `LAUNCHER_DIR`, executing `LAUNCHER="${LAUNCHER_DIR}/FusionLauncher.exe"` fails if that directory lacks `FusionLauncher.exe.ini`. `FusionLauncher.exe` looks for its `.ini` in its own working directory and throws the "missing or incomplete / Please re-install" message.

### Fix (automated in `scripts/fusion360`)
The launcher script now automatically verifies if `${LAUNCHER_DIR}/FusionLauncher.exe.ini` exists before executing. If missing, it dynamically generates the UTF-16LE configuration file with the proper byte-order mark (BOM):

```bash
if [[ ! -f "${LAUNCHER_DIR}/FusionLauncher.exe.ini" ]]; then
    DIR_NAME="$(basename "$LAUNCHER_DIR")"
    python3 -c "
target_cmd = f'\"\"C:\\\\users\\\\steamuser\\\\AppData\\\\Local\\\\Autodesk\\\\webdeploy\\\\production\\\\${DIR_NAME}\\\\Fusion360.exe\"\"'
ini_content = f'[Launcher]\r\nstream = production\r\nauid = AutodeskInc.Fusion360\r\ncmd = {target_cmd}\r\nglobal = False\r\n\r\n'
with open('${LAUNCHER_DIR}/FusionLauncher.exe.ini', 'wb') as f:
    f.write(ini_content.encode('utf-16'))
" 2>/dev/null || true
fi
```

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

## 15. Updating Fusion & Understanding WebDeploy Streamer Cleanup

Fusion self-updates replace the `webdeploy/production/<hash>` directory. Because the launcher auto-detects the live deployment, no path edit is needed after an update.

### What happens during an update ("restart to update")
1. Autodesk downloads the new build into a brand-new payload directory (e.g., `a3178fba...`).
2. Autodesk updates `FusionLauncher.exe.ini` in the persistent launcher folder (`6a0c9611...`) to point to the new `Fusion360.exe`.
3. In the background, `streamer.exe` is invoked to uninstall the older version:
   ```text
   streamer.exe --quiet --cleanup -p uninstall -s production
   ```
4. During this cleanup phase, an older folder (e.g., `736d2b4c...` from an earlier release) may remain visible on disk until all files and registry keys are unlinked.

### The "corrupt update / reinstall loop" trap
If you inspect `production/` immediately after a "restart to update" notice, you might see an older directory that appears to have stale binaries (e.g., older timestamps or sizes). It is easy to mistake this for a failed or corrupt update.

If you manually delete or move that folder while the streamer is running:
* `autodesk.webdeploy.streamer.log` will flood with thousands of warnings:
  ```text
  WARNING :: Could not remove non-existant file: \\?\c:\...\production\<old-hash>\...
  ```
  This is harmless — the uninstaller is simply noting that files it wanted to delete were already missing.
* If your launcher script drops back to the new build folder which lacks `FusionLauncher.exe.ini`, you will get the **"Please re-install the application"** message (see §4).
* It can feel like WebDeploy is rejecting the install because of the deleted folder, but it is actually just the missing `.ini` in the new folder.

Do **not** wipe the prefix or move folders manually during updates. Let the streamer finish, and ensure the active folder has its `.ini`.

To trigger an update check or run update tasks without launching the full CAD GUI, use `scripts/fusion360-update`.

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

## 17. Stale ADPSDK Client Service (`CS.json`)

Autodesk's Analytics & Data Platform SDK (`ADPSDK`) records the state of its background service in:

```text
~/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Roaming/Autodesk/ADPSDK/CS.json
```

It contains the absolute Windows path to `ADPClientService.exe`:

```json
{
    "path": "C:\\users\\steamuser\\AppData\\Local\\Autodesk\\webdeploy\\production\\<old-hash>\\ADPClientService.exe",
    "status": 1,
    "statusMessage": "Running"
}
```

When an older deployment is uninstalled or removed, `CS.json` can still reference the uninstalled folder path. This can prevent ADPSDK from starting or connecting to the service in the active deployment.

### Fix
Either update the path in `CS.json` to the current production folder:

```bash
PREFIX="$HOME/.local/share/fusion360/prefix"
CURRENT_HASH="$(for d in "$PREFIX/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production"/*; do
    if [[ -f "$d/Fusion360.exe" ]]; then basename "$d"; fi
done | head -n 1)"

sed -i "s|production\\\\[^\\\\]*\\\\ADPClientService.exe|production\\\\${CURRENT_HASH}\\\\ADPClientService.exe|" \
    "$PREFIX/drive_c/users/steamuser/AppData/Roaming/Autodesk/ADPSDK/CS.json"
```

Or delete `CS.json` completely so Fusion recreates it on the next launch:

```bash
rm -f "$HOME/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Roaming/Autodesk/ADPSDK/CS.json"
```

## 18. Recovering from a Broken Update State without Reinstalling

If Fusion stops launching after an update and you see the "Please re-install" dialog:

1. **Terminate all stale Wine/Proton/Fusion processes:**
   ```bash
   "$HOME/.local/share/fusion360/proton/GE-Proton11-3/files/bin/wineserver" -k || true
   pkill -f 'GE-Proton11-3' || true
   pkill -f 'FusionLauncher.exe' || true
   pkill -f 'Fusion360.exe' || true
   pkill -f 'umu-run' || true
   ```
2. **Find which production folder has the live `Fusion360.exe`:**
   ```bash
   for d in ~/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production/*; do
       if [[ -f "$d/Fusion360.exe" ]]; then echo "Live deployment: $d"; fi
   done
   ```
3. **Verify `FusionLauncher.exe.ini` exists in that folder:**
   With the updated `scripts/fusion360`, this is handled automatically on launch. To verify manually:
   ```bash
   ls -la "$LIVE_DIR/FusionLauncher.exe.ini"
   ```
4. **Clean stale ADPSDK state:**
   ```bash
   rm -f ~/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Roaming/Autodesk/ADPSDK/CS.json
   ```
5. **Launch Fusion:**
   ```bash
   ~/.local/bin/fusion360
   ```

## 19. "Unable to sign in: Your system settings, firewall, or antivirus are likely preventing sign in"

### Symptom
On startup, a blocking modal dialog appears titled **"Unable to sign in"**:

```text
Your system settings, firewall, or antivirus are likely preventing sign in.
To resolve this issue, follow the instructions in the link below.
```

In `AppData/Local/Autodesk/Neutron Platform/logs/AppLogFile*.log`:

```text
IDSDKAuth: idsdk_set_product_config failed with error IDSDK_E_SERVER_PROCESS_NOT_READY
IDSDKAuth: Showing blocking Quit dialog. idsdk=IDSDK_E_SERVER_PROCESS_NOT_READY operation=idsdk_set_product_config title=Unable to sign in
```

### Root Cause
This error is rarely caused by a literal Linux firewall or antivirus. It occurs when `AdskIdentityManager.exe` fails to start, bind to shared memory, or handshake with Fusion:
1. **Stale IDSDK IPC Lock Files**: An unclean exit (or process termination via `wineserver -k`) leaves stale `.lock` files in:
   ```text
   drive_c/ProgramData/Autodesk/IDSDK/<user-hash>/interprocess/01000000/Autodesk.IDSDK.StartupLock.lock
   drive_c/ProgramData/Autodesk/IDSDK/<user-hash>/interprocess/01000000/IDSDKAppState-v2.lock
   ```
   When Fusion restarts, `AdskIdentityManager.exe` fails to acquire the startup mutex and times out.
2. **WebView2 Flag Overrides**: Injecting experimental Chromium flags via `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` (such as disabling SmartScreen, tracking prevention, or feature flags) can break the security and callback pipeline of Identity Manager's embedded browser.

### Fix
Purge any lingering `.lock` files:

```bash
PREFIX="$HOME/.local/share/fusion360/prefix"
rm -f "$PREFIX/drive_c/ProgramData/Autodesk/IDSDK/"*/interprocess/01000000/*.lock
```

The updated `scripts/fusion360` script purges these lock files automatically before launching and upon session cleanup.

## 20. Viewport Stutter, 120Hz Frame Pacing, and Hybrid Laptop GPU Power Management

### Symptom
Viewport navigation (orbit, pan, zoom) feels laggy and micro-stuttery irrespective of graphic settings on high-refresh (120Hz/144Hz) Wayland displays, even when GPU render times are low (~5ms).

### Root Causes & Solutions

1. **Wayland 120Hz Frame Pacing & Double-VSync Conflicts**:
   When DXVK renders with `dxgi.syncInterval = 0` unthrottled, frames arrive at irregular intervals into KWin's compositor queue on XWayland. KWin composites at 120Hz, resulting in dropped frames and visual judder.
   - **Solution**: Configure `scripts/dxvk.conf`:
     - `dxgi.syncInterval = 0` + `dxvk.tearFree = True`: Enables Vulkan **Mailbox presentation mode** (delivers the freshest rendered frame at 120Hz with zero queue stalls and no tearing).
     - `dxgi.maxFrameRate = 120` & `dxvk.maxFrameRate = 120`: Caps frame delivery to the panel's 120Hz frequency.
     - `dxgi.maxFrameLatency = 1` & `d3d11.maxFrameLatency = 1`: Drops input queue depth to 1 frame for instant mouse response.

2. **Hybrid CPU Core Affinity (Intel 12th-Gen+ P/E Cores)**:
   On hybrid architectures (e.g. Alder Lake Intel i7-12700H), the Linux kernel scheduler can place the main CAD render thread or `wineserver` onto low-power Efficiency cores (CPUs 8–11).
   - **Solution**: `scripts/fusion360` pins the process tree to Performance cores (`taskset -c 0-7`).

3. **Background Accessibility Tree Crawling (`xalia.exe`)**:
   Proton enables Xalia accessibility helper by default, which inspects Qt and WebView2 accessibility trees on every UI change, burning 25–35% CPU in the background.
   - **Solution**: Export `PROTON_USE_XALIA=0` in the launcher.

4. **NVIDIA Laptop GPU Power Management (Runtime D3 / D3cold vs P8 State)**:
   Unlike games that render constantly, CAD applications render **on demand** (0 FPS when looking at a model; burst of 120 FPS when dragging the mouse).
   - Under Linux, NVIDIA's dynamic frequency scaling (`nvidia-powerd` / PowerMizer) drops the GPU down to **P8 state** (210 MHz core / 405 MHz VRAM) when 0 FPS is rendered.
   - **Do NOT enable permanent persistence mode (`nvidia-smi -pm 1`) on laptops**, as it forces the discrete GPU to stay awake at 5–10W constantly and breaks PCIe Runtime D3 (D3cold 0W power-down).
   - The tuned DXVK Mailbox presentation mode provides smooth 120Hz navigation while still allowing the GPU to power down to 0W when Fusion exits.
