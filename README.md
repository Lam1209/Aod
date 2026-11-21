# SimpleAOD (v0.1)

Always On Display for OLED iPhones (written for the iPhone X).
When the screen would turn off, it stays on at a very low brightness and shows a black
screen with the clock, date and battery level. OLED black = pixels off, so the battery
cost is small. The content moves a little every minute (pixel shift) to protect the panel.

**Status: untested.** It was written without access to a device. It relies on
SpringBoard's backlight code, which differs between iOS versions (best chance on iOS 12-14;
iOS 15/16 may need changes).

## Build the .deb

### Option A: Mac or Linux with Theos
1. Install Theos + an iOS SDK (https://theos.dev/docs/installation).
2. If your jailbreak is **rootless** (palera1n rootless, Dopamine...), uncomment
   `export THEOS_PACKAGE_SCHEME = rootless` in the `Makefile`.
3. Run `make package`. The .deb appears in `packages/`.

### Option B: no Mac (GitHub)
1. Create a new GitHub repository and upload this whole folder (keep `.github/workflows/build.yml`).
2. Open the **Actions** tab, run **Build deb** (it also runs on every push).
3. Download the `SimpleAOD-deb` artifact when it finishes (unzip it to get the .deb).

## Install
Open the .deb with Filza (or `dpkg -i`), then respring. Settings > SimpleAOD
(needs PreferenceLoader). Lock the phone: the screen should stay on, dim, with the clock.

## Settings
| Option | Default | What it does |
|---|---|---|
| Enabled | on | Master switch |
| Only while charging | off | Use AOD only when plugged in |
| Double-tap to wake | on | Off = single tap (more accidental wakes in a pocket) |
| Pixel shift | on | Moves the clock around every minute (burn-in protection) |
| Brightness | 0.10 | Backlight level while AOD is showing |

No settings pane? Edit `/var/mobile/Library/Preferences/com.local.simpleaod.plist`
(keys: `enabled`, `chargingOnly`, `doubleTap`, `pixelShift`, `brightness`) and lock the phone again.

AOD is skipped below 10 % battery (unless charging) and during phone calls.

## If it doesn't work
The tweak logs every backlight call. Lock the phone and read the log
(`idevicesyslog | grep SimpleAOD` from a Mac/PC, or the Console app):

- `_animateBacklightToFactor:0.000 ...` then `AOD on`, but the screen still goes black:
  your iOS blanks the display somewhere else. Send me the iOS version and the log lines.
- No `_animateBacklightToFactor` / `setBacklightFactor` lines at all: those methods don't
  exist on your iOS version, so the hook has to be pointed at a different method.
- Clock frozen after a while: the device is idle-sleeping despite `preventIdleSleep`.
- SpringBoard crashes / safe mode: remove the package, tell me the iOS version.

## Known limitations
- No notification icons on the AOD (tap to wake shows the lock screen as usual).
- Pocket detection is not implemented, so use double-tap to wake.
- Small extra battery use is expected (roughly 1-3 % per hour on OLED for similar tweaks).

## Uninstall
Remove "SimpleAOD" in Sileo/Cydia/Zebra, or `dpkg -r com.local.simpleaod`, then respring.
