# Autodesk Authentication: The Critical Part

## Symptom

Fusion itself could launch and display the Autodesk sign-in screen. Chrome authentication completed, but after:

```text
Open Autodesk Identity Manager?
```

Fusion stayed on the sign-in screen.

## What was verified

The callback URI was successfully delivered to the Linux desktop handler as:

```text
adskidmgr:/login?... 
```

The actual OAuth callback contains sensitive authentication material and is intentionally not reproduced in this repository.

Autodesk Identity Manager logs showed:

```text
Failed to refresh token. Not logged in.
AdSSO server app does not found
```

The network test itself succeeded, and Fusion successfully communicated with the Identity Manager IPC server. Therefore the failure was narrowed to the authentication callback / Identity Manager integration rather than basic networking or Fusion installation.

## What did not solve it

### `FUSION_IDSDK=false`

Tested by launching `Fusion360.exe` directly with:

```bash
FUSION_IDSDK=false
```

The current Fusion build still loaded `IdSDKPlugin.dll` and launched Identity Manager. It therefore did not bypass the modern identity stack on this installation.

### `WINEDLLOVERRIDES="bcp47langs="`

Also tested. It did not, by itself, complete Autodesk authentication on this build.

The final launcher nevertheless sets both known overrides:

```bash
export WINEDLLOVERRIDES="bcp47langs=,icuuc=n"
```

`bcp47langs=` is the historical Fusion/Wine compatibility override; `icuuc=n`
disables Wine's ICU shim, which interferes with the .NET/CLR bits that Fusion
and Identity Manager load.

## Successful fix

The final setup deliberately uses two launch paths.

### Main Fusion application

```text
FusionLauncher.exe
    ↓
umu-run
    ↓
Steam Linux Runtime 4
    ↓
GE-Proton 11-3
```

### Autodesk callback

```text
Chrome
  ↓
adskidmgr://
  ↓
KDE URI handler
  ↓
GE-Proton's bundled Wine binary
  ↓
AdskIdentityManager.exe
  ↓
same WINEPREFIX
```

The crucial difference was the callback command.

The failing path was conceptually:

```bash
umu-run AdskIdentityManager.exe "adskidmgr:/login?..."
```

The working path was:

```bash
"$PROTON/files/bin/wine" "$IDENTITY_MANAGER" "$@"
```

with:

```bash
export WINEPREFIX="$HOME/.local/share/fusion360/prefix"
```

where `$PROTON` is the GE-Proton 11-3 directory (either
`~/.local/share/fusion360/proton/GE-Proton11-3` or
`~/.steam/steam/compatibilitytools.d/GE-Proton11-3`).

This finally allowed Autodesk authentication to complete and Fusion to enter the normal workspace.

## Why this matters

The successful architecture is not simply "run Fusion with Proton". The browser callback is a separate IPC/authentication path, and it must reach the correct Identity Manager instance in the same Wine environment.

## Diagnostics used during the investigation

Check Identity Manager:

```bash
pgrep -af 'AdskIdentityManager|msedgewebview2|FusionLauncher|Fusion360|umu-run|GE-Proton11-3'
```

Inspect the Identity Manager log:

```bash
LOG="$HOME/.local/share/fusion360/prefix/drive_c/users/steamuser/AppData/Local/Autodesk/Identity Services/Log/IdServices.log"
tail -200 "$LOG"
```

Search authentication-related entries:

```bash
grep -i -E 'Login|OAuth|Token|AdSSO|SSO|callback|error|failed' "$LOG" | tail -100
```

Verify the desktop handler:

```bash
gio mime x-scheme-handler/adskidmgr
```
