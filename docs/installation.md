# Installation and Final Working Setup

This is the condensed reproducible procedure from the successful Fedora 44 installation.

## 1. Host baseline

Observed host:

```text
Fedora Linux 44 (KDE Plasma Desktop Edition)
Kernel: 7.2.8-200.fc44.x86_64
Session: Wayland
Desktop: KDE Plasma
Intel Alder Lake-P UHD Graphics
NVIDIA GeForce RTX 3050 6GB Laptop GPU
NVIDIA driver: 615.71.09
RAM: 15.3 GiB
Swap: 8 GiB
```

Baseline commands:

```bash
cat /etc/os-release | grep -E '^(NAME|VERSION|VERSION_ID)='
uname -r
echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE"
echo "XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP"
lspci -nnk | grep -A4 -E 'VGA|3D|Display'
nvidia-smi
vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverName|driverInfo' | head -20
steam --version
```

## 2. GE-Proton

The runner is GE-Proton 11-3. Download `GE-Proton11-3.tar.gz` from the
[GE-Proton 11-3 release](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton11-3).

It may live in the Steam compatibility-tools directory or in a dedicated Fusion
tree. The tested setup keeps it under the Fusion directory:

```text
~/.local/share/fusion360/proton/GE-Proton11-3
```

Extract it there:

```bash
mkdir -p ~/.local/share/fusion360/proton
tar -xzf ~/Downloads/GE-Proton11-3.tar.gz -C ~/.local/share/fusion360/proton
ls -d ~/.local/share/fusion360/proton/GE-Proton11-3     # must exist
```

The Steam location also works and the launchers auto-detect it:

```text
~/.steam/steam/compatibilitytools.d/GE-Proton11-3
```

If using Steam's compatibility-tools directory, extract the archive there and restart Steam.

## 3. UMU launcher

Fedora's configured repositories did not provide `umu-launcher`, so UMU was installed manually.

Download from the [umu-launcher releases](https://github.com/Open-Wine-Components/umu-launcher/releases).
Two easy options:

```bash
# Option A: pipx (installs ~/.local/bin/umu-run)
pipx install umu-launcher

# Option B: the Fedora .rpm from the releases page
sudo dnf install ~/Downloads/umu-launcher-1.4.4.fc43.x86_64.rpm   # match the version/arch
```

Final executable:

```text
~/.local/bin/umu-run
```

Verify:

```bash
export PATH="$HOME/.local/bin:$PATH"
command -v umu-run
umu-run --version
```

Observed:

```text
umu-launcher version 1.4.4
```

Persist the PATH:

```bash
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc || \
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

## 4. Dedicated Fusion prefix

```bash
mkdir -p ~/.local/share/fusion360/prefix
```

Final prefix:

```text
~/.local/share/fusion360/prefix
```

## 5. Autodesk installer

There is no Linux build of Fusion — you download Autodesk's **Windows** installer
and run it through umu + GE-Proton.

1. Sign in to (or create) an [Autodesk account](https://www.autodesk.com).
2. Get a license: free [personal use](https://www.autodesk.com/products/fusion-360/personal),
   a 30-day trial, or education.
3. Go to **Products and Services → Fusion → Download**. The downloader is the
   Windows client installer and usually lands in `~/Downloads` as:

```text
~/Downloads/Fusion Client Downloader.exe
```

(If your file has a different name, use that path below.)

Initial install:

```bash
WINEPREFIX="$HOME/.local/share/fusion360/prefix" \
PROTONPATH="$HOME/.local/share/fusion360/proton/GE-Proton11-3" \
umu-run "$HOME/Downloads/Fusion Client Downloader.exe"
```

(If GE-Proton is in the Steam directory, point `PROTONPATH` there instead.)

UMU initialized Steam Linux Runtime 4 automatically.

## 6. Find the installed deployment

Fusion was installed under:

```text
~/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production/
```

Autodesk installs each build into a `webdeploy/production/<hash>` directory and a
self-update replaces the previous one. **Do not hard-code the hash.** The
launcher detects the newest directory that contains both `FusionLauncher.exe` and
`Fusion360.exe` at launch time. List what is present:

```bash
for d in "$HOME/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production"/*/; do
    printf '%s  F360=%s LAUNCH=%s\n' "$(basename "$d")" \
        "$([ -f "$d/Fusion360.exe" ] && echo y || echo n)" \
        "$([ -f "$d/FusionLauncher.exe" ] && echo y || echo n)"
done
```

The active deployment in the latest test was `736d2b4c5e6b95e77c11721da222cf21c6a1fc1f`.
Older folders (for example one containing `FusionLauncher.exe` but no
`Fusion360.exe`) are stale and are ignored.

## 7. Fusion launcher configuration (`FusionLauncher.exe.ini`)

If a deployment contains `FusionLauncher.exe` but no `FusionLauncher.exe.ini`,
launching it produces:

```text
Configuration file FusionLauncher.exe.ini is missing or incomplete
```

An older production directory can contain a valid `.ini` whose `cmd` points at
the current `Fusion360.exe`. Copy it into the current deployment:

```bash
DEPLOY="$HOME/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production"
# older deployment that has the .ini
OLD="$DEPLOY/6a0c9611291d45bb9226980209917c3d"
# current deployment
NEW="$DEPLOY/736d2b4c5e6b95e77c11721da222cf21c6a1fc1f"
cp "$OLD/FusionLauncher.exe.ini" "$NEW/FusionLauncher.exe.ini"
```

Verify:

```bash
cat "$NEW/FusionLauncher.exe.ini"
```

## 8. Final Fusion launcher

Install `scripts/fusion360` as:

```text
~/.local/bin/fusion360
```

```bash
install -Dm755 scripts/fusion360 ~/.local/bin/fusion360
```

The launcher:

- detects GE-Proton (dedicated tree or Steam compatibility-tools directory);
- detects the newest live Fusion deployment;
- refuses to start a second instance while Fusion is running;
- sets `WINEPREFIX`, `PROTONPATH`, `QT_D3D_NO_FLIP=1` and
  `WINEDLLOVERRIDES="bcp47langs=,icuuc=n"`;
- **does not** force the discrete GPU (see `docs/graphics.md`);
- runs `FusionLauncher.exe` via UMU and cleans up Proton/Wine processes when
  Fusion exits.

## 9. Final Autodesk callback handler

Install:

```text
~/.local/bin/fusion-adskidmgr-direct
```

```bash
install -Dm755 scripts/fusion-adskidmgr-direct ~/.local/bin/fusion-adskidmgr-direct
```

The important part is:

```bash
WINE="$PROTON/files/bin/wine"
exec "$WINE" "$IDENTITY_MANAGER" "$@"
```

Do **not** replace this with `umu-run` for the callback on this tested configuration; that path reproduced the authentication failure.

## 10. Register the URI handler

Install:

```bash
install -Dm644 scripts/adskidmgr.desktop ~/.local/share/applications/adskidmgr.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null || true
xdg-mime default adskidmgr.desktop x-scheme-handler/adskidmgr 2>/dev/null || true
```

Verify:

```bash
gio mime x-scheme-handler/adskidmgr
```

Expected:

```text
Default application for “x-scheme-handler/adskidmgr”: adskidmgr.desktop
```

## 11. KDE application launcher

Install:

```bash
install -Dm644 scripts/autodesk-fusion360.desktop ~/.local/share/applications/autodesk-fusion360.desktop
install -Dm644 scripts/autodesk-fusion360-update.desktop ~/.local/share/applications/autodesk-fusion360-update.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null || true
kbuildsycoca6 --noincremental 2>/dev/null || true
```

The entry should appear in the KDE application launcher as `Autodesk Fusion 360`.

## 12. Normal use

Normal launch:

```bash
~/.local/bin/fusion360
```

Or start `Autodesk Fusion 360` from KDE's application menu.

The browser authentication flow is handled automatically through `adskidmgr://` once the URI handler is registered.

## 13. Reboot persistence

All working configuration is stored under the user's home directory. No diagnostic command is required at normal launch.

After reboot:

```text
KDE application launcher
        ↓
Autodesk Fusion 360
        ↓
Fusion / GE-Proton
        ↓
Autodesk authentication if required
        ↓
Fusion workspace
```

If a cold boot ever opens with a black viewport, confirm that no offload
variables are set in the launcher — see `docs/graphics.md`.

## 14. GPU validation

With Fusion running:

```bash
nvidia-smi
```

The working installation showed approximately:

```text
Fusion360.exe        ~1670 MiB GPU memory
msedgewebview2.exe      ~89 MiB GPU memory
```

on the RTX 3050.

`0 %` GPU utilization at a single instant is not evidence of missing
acceleration; the VRAM allocation and process visibility are the useful signals.
