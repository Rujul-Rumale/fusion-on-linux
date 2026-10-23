# Graphics: the black canvas, the GUI-init crash, and the GPU-present path

This is the second half of the Fusion-on-Fedora story. Authentication was one
problem; a hostile graphics environment was the other. Everything here was
learned on a hybrid **Intel iGPU + NVIDIA RTX 3050** laptop running **KDE Plasma
Wayland** with Fusion's windows on XWayland.

## Two symptoms, one area

Two problems appeared on this hardware:

1. **Black 3D canvas.** Fusion's UI (ribbon, browser, toolbars) drew fine, but
   the viewport where the model should be was black.
2. **Silent crash on a fresh boot.** On a cold boot, launching Fusion could die
   right at Qt GUI initialization — no window, no error dialog, no core dump.

Both traced back to how Fusion's Qt/D3D11 rendering reaches the screen on a
hybrid-GPU, Wayland-composited desktop.

## Root cause: the force-discrete-GPU variables

The original launcher exported these to "use the NVIDIA GPU":

```bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
```

**They were the problem, not the fix.** Removing all three:

- stopped the fresh-boot crash at Qt GUI init, and
- produced a working (non-black) canvas.

### What the logs showed

On the crashing launch, Fusion's Neutron `AppLogFile` stopped mid-init:

```text
PERF: initializeGUI1 START.
Set appUserModelId from config: AutodeskInc.Fusion360
<log ends - no signal, no core, no OOM>
```

On a working launch the same sequence continued:

```text
PERF: initializeGUI1 START.
Set appUserModelId from config: AutodeskInc.Fusion360
PERF: initializeGUI1 END.
PERF: initializeGUI2 START.
...
```

So the failure was inside GUI initialization, before the second init stage.

### Why forcing offload hurts here

This laptop is a hybrid setup:

- the Intel iGPU drives the eDP-1 panel and **KWin composites on Intel**;
- the NVIDIA GPU has no connected connector of its own.

Under XWayland + KWin, the canvas is rendered by DXVK on the NVIDIA GPU and then
presented through the Intel-composited X server. Forcing `PRIME` offload /
NVIDIA GLX changes which GL/Vulkan ICDs and present path are selected, which
breaks that cross-GPU present — hence the black canvas (and, on a cold boot, the
init crash).

### You do not lose the discrete GPU

DXVK picks the NVIDIA GPU on its own. The DXVK log confirms it with no offload
variables set at all:

```text
Creating device: ... Driver NVIDIA 615.71.9
```

The Fusion adapters are still enumerated with NVIDIA preferred:

```text
QT RHI: Direct3D11
adapter 0: NVIDIA GeForce RTX 3050 ...
adapter 1: Intel UHD Graphics ...
```

So the "performance" the force variables were meant to buy is already there.

## Keep `QT_D3D_NO_FLIP=1`

Fusion's Qt front end can use either flip-model or blt-model swapchains for
Direct3D 11 presentation. Under DXVK, **flip-model swapchains come out black**.
Fusion sets `QT_D3D_NO_FLIP=1` itself in the working path; the launcher pins it
too so an app-side change cannot silently drop you back onto the flip path:

```bash
export QT_D3D_NO_FLIP=1
```

Do **not** pass `--disable-gpu` either — that also removes the canvas.

## Do not launch `Fusion360.exe` directly

Launch `FusionLauncher.exe`. The launcher sets up product/environment state that
the application expects; starting `Fusion360.exe` on its own comes up with a
black canvas.

## Do not stack two instances

Running two `umu-run` instances against the same prefix makes them fight over
the Wine lock. The observed result is a **black canvas plus severe CPU/disk
thrash**. The launcher therefore refuses to start when Fusion is already
running:

```bash
if pgrep -f 'FusionLauncher.exe' >/dev/null 2>&1 || pgrep -f 'Fusion360.exe' >/dev/null 2>&1; then
    echo "Fusion 360 is already running." >&2
    exit 0
fi
```

## `icuuc=n`

The launcher sets:

```bash
export WINEDLLOVERRIDES="bcp47langs=,icuuc=n"
```

`bcp47langs=` is a long-standing Fusion/Wine compatibility override. `icuuc=n`
disables Wine's ICU shim, which otherwise interferes with the .NET/CLR bits
Fusion loads.

## XWayland, not native Wayland

Fusion's windows are XWayland. Shells that export `EGL_PLATFORM=wayland`,
`GDK_BACKEND=wayland` or `QT_WAYLAND_RECONNECT` can push WebView2's GPU process
onto the wrong path. The launcher clears them so a launch from an IDE/tool shell
behaves like a launch from the KDE menu:

```bash
unset EGL_PLATFORM GDK_BACKEND QT_WAYLAND_RECONNECT || true
```

## Benign log noise: `Failed to open shared NT handle`

A DXVK session can emit thousands of lines like:

```text
warn: DxgiSwapChain::CreateSwapChain: Failed to open shared NT handle ...
```

This is a known DXVK 3.x + Wine 11.x issue (upstream `doitsujin/dxvk#5771`). It
also appears on fully-working systems and is **not** the black-canvas cause. The
launcher runs with `DXVK_LOG_LEVEL=none` to keep the console clean anyway.

## How to diagnose a black canvas

Set `DXVK_LOG_LEVEL=info` (or run `DXVK_HUD=1`) for a session and watch the
first few hundred lines:

```bash
DXVK_LOG_LEVEL=info ~/.local/bin/fusion360 2> ~/fusion-dxvk.log
```

Look for the device-selection and swapchain lines:

```text
Creating device: ... Driver NVIDIA <version>
Creating swapchain: ... format ... present mode ...
```

- If the device is NVIDIA and swapchains are created, rendering is reaching DXVK
  and the problem is in present/compositing (GPU offload vars, flip model,
  double-launch).
- If the device is `llvmpipe` / software, the GPU selection itself is wrong.

## DXVK Tuning for 120Hz Displays & Latency

Fusion's viewport can suffer from micro-stutter on high-refresh (120Hz/144Hz) Wayland displays due to uneven frame pacing between DXVK and KWin.

The repository includes a tuned `scripts/dxvk.conf` installed to `~/.local/share/fusion360/dxvk.conf`:

```ini
# Frame pacing & presentation for 120Hz display
dxgi.syncInterval = 0
dxvk.tearFree = True

# Match panel refresh rate to prevent XWayland compositor buffer judder
dxgi.maxFrameRate = 120
dxvk.maxFrameRate = 120

# Minimize input lag during 3D navigation (1-frame queue instead of 3)
dxgi.maxFrameLatency = 1
d3d11.maxFrameLatency = 1

# Pipeline & barrier optimization for high-fidelity effects
d3d11.relaxedBarriers = True
d3d11.relaxedGraphicsBarriers = True

# Multi-threaded shader & pipeline compilation across CPU cores
dxvk.numCompilerThreads = 8
dxvk.enableGraphicsPipelineLibrary = True
dxvk.enableMemoryDefrag = True
```

- **`dxvk.tearFree = True` + `dxgi.syncInterval = 0`**: Activates Vulkan **Mailbox presentation mode**, which provides the lowest latency possible without tearing or double-buffering stalls.
- **`dxgi.maxFrameRate = 120`**: Prevents the GPU from rendering un-paced frames that KWin has to drop, eliminating visual judder.
- **`PROTON_USE_XALIA=0`**: Disables Proton's accessibility tree scanner, reclaiming 25–35% CPU.
- **`taskset -c 0-7`**: Locks Fusion's render threads to high-clock P-cores on Intel hybrid 12th-Gen+ CPUs.

## The short version

```text
Do:
  launch FusionLauncher.exe via umu + GE-Proton
  QT_D3D_NO_FLIP=1
  dxvk.tearFree = True & maxFrameRate = 120 in dxvk.conf
  PROTON_USE_XALIA=0
  pin to P-cores on hybrid CPUs (taskset -c 0-7)
  one instance at a time
  let DXVK pick the GPU

Do not:
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __VK_LAYER_NV_optimus=NVIDIA_only
  enable permanent persistence mode (nvidia-smi -pm 1) on laptops
  pass --disable-gpu
  launch two copies
```
