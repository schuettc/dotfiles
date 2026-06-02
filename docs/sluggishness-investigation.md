# Sluggishness investigation (2026-06-01)

## Status: OPEN — persists, rebooting to test

## What it is NOT
Checked and ruled out:
- **WindowServer CALayer leak** (the cmux problem) — gone since migration. WindowServer 11-16%, not 40%+.
- **Thermal throttling** — `pmset -g therm`: "No thermal warning level recorded".
- **Memory pressure** — 47 GB free, 0 swap, ~1 GB compressor, 95% available.
- **CPU saturation** — load 3.5 on 16 cores, 85% idle.
- **Stuck processes** — none in uninterruptible state.
- **Startup items** — cleaned 6 dead orphans; they weren't running anyway (~0 MB).
- **Session pileup** — was 33 tmux sessions / 16 Claudes / 20 GB; cleaned to ~5.
- **Runaway pytest** — was 15 GB single-process; fixed with pytest-xdist + timeout in now-playing/pi.

## Leading hypothesis: UI compositing latency from continuous redraw
Symptom signature: feels slow, but CPU 85% idle + no throttle + memory fine.
That points at rendering, not compute. The tell:
**WindowServer (~16%) + Ghostty (~12%) burning CPU continuously even at "idle."**

Likely cause: multiple Ghostty panes with LIVE ANIMATED content (Claude
"thinking" spinners, yazi, progress bars) each forcing continuous repaint +
recompositing. Several concurrent Claude sessions = steady redraw stream =
laggy input/scroll despite idle CPU.

## Post-reboot test plan
1. One Ghostty window, no Claude → should be snappy.
2. Shell + yazi only → still snappy?
3. Spin up Claude sessions across tabs → does lag return AS animated panes are added?
   - If yes → confirmed redraw-driven. Fix = workflow (fewer live spinners at once)
     or Ghostty render settings (window-vsync, custom-shader, etc.), NOT hardware.

## Things to try if it's redraw
- Reduce simultaneous live Claude panes.
- Check Ghostty `window-vsync`, animation settings.
- `sudo sample WindowServer 3` while sluggish → see what it's compositing.
- Check GPU: `ioreg -l | grep "Device Utilization"`.
- External display in scaled (HiDPI) mode multiplies WindowServer compositing cost — check display resolution.

---

## RESOLVED (2026-06-01): It's the Bluetooth mouse, not compute

Symptom narrowed: **mouse CURSOR movement lags**, everything else idle.

Measured & ruled out (this is the full elimination):
- WindowServer: `sudo sample 420 5` → 91% idle (mach_msg), 8% normal compositing.
  NOT the cmux-style flat prepare_layer recursion. Exonerated.
- Displays: CGGetOnlineDisplayList = 1. The external-0..3 CA threads are stale
  pipelines from past monitors, all idle. NOT phantom-display compositing.
- tmux status bar: one full git-status refresh cycle = 0.02s CPU. Negligible.
- Memory 47GB free / 0 swap, no thermal throttle, load 3.5/16, 85% CPU idle.

Standing anomaly → ROOT CAUSE:
- **5 Logitech MX Master mice paired over Bluetooth** (3 Mac, two 3S, a 4) + Magic Keyboard.
- macOS cursor is hardware-composited and never lags from CPU load. A laggy
  cursor on an idle machine = delayed mouse-move events = Bluetooth contention /
  weak link. MX Master over BT has documented cursor-stutter on macOS.

Definitive test: trackpad (internal USB HID) smooth vs MX Master (BT) laggy.

Fix, in order of impact:
1. Use the Logi Bolt USB receiver instead of Bluetooth (lowest latency, no BT congestion).
2. Remove the 4 unused paired MX Master mice (System Settings > Bluetooth).
3. Charge the active mouse — low battery = weak BT signal = stutter.
4. Install Logi Options+ if staying on Bluetooth.

NOTE: a reboot will NOT fix this — it's the input link, not software state.

---

## CORRECTION (2026-06-01): NOT Bluetooth — mouse is on Logi Bolt via CalDigit TB dock

The BT theory above was WRONG — the active mouse uses the Logi Bolt USB
receiver, not Bluetooth. The 5 paired BT mice are stale pairings, irrelevant.

Measured USB topology (ioreg -p IOUSB):
  CalDigit Thunderbolt dock (AppleUSBXHCIFL1100)
    └─ GenesysLogic USB2.1 Hub
        ├─ Logitech "USB Receiver"  ← the Logi Bolt mouse receiver
        └─ Keychron K1 SE keyboard
  Logitech StreamCam → SEPARATE controller (AppleASMediaUSBXHCI) — camera ruled out.

Docked MacBook (has "Apple Internal Keyboard/Trackpad"). The CalDigit dock
almost certainly also drives the 5120x1440@120Hz display over the same TB link.

Hypothesis (grounded in topology): Thunderbolt/USB contention on the dock —
display pushing ~17Gbps DP at 120Hz on the same TB link as the dock's USB hub —
causes mouse-report polling jitter → cursor lag while machine is otherwise idle.

DEFINITIVE TEST: move the Logi Bolt receiver from the dock to a DIRECT MacBook
USB port. Smooth → dock path confirmed. Still laggy → sample cursor thread while moving.

Fixes if confirmed:
1. Keep Bolt receiver in a direct Mac port (not behind the dock/display TB link).
2. Drop display 120Hz → 60Hz (halves DP bandwidth, frees TB headroom) — quick toggle to test.

---

## ✅ SOLVED & CONFIRMED (2026-06-01)

A/B test result: same MX Master mouse —
  - Logi Bolt receiver plugged into CalDigit TB dock → cursor LAGGY
  - Switched mouse to Bluetooth (direct to Mac) → "much much better"

Plus the under-movement WindowServer sample proved WS was IDLE while moving
(cursor/IOHIDService/render threads all parked in CFRunLoopRun) — so the Mac's
cursor rendering was never the bottleneck. The lag was in EVENT DELIVERY from
the dock's USB path, contended with the 5120x1440@120Hz display on the same
Thunderbolt link.

ROOT CAUSE: Logi Bolt receiver on the CalDigit Thunderbolt dock; dock USB
event-delivery jitter under display bandwidth load → laggy cursor on an
otherwise-idle machine.

FIX (best → ok):
  1. Move the Bolt receiver to a DIRECT MacBook USB port (lowest latency).
  2. Stay on Bluetooth (current; already much better).
  (Do NOT bother dropping to 60Hz — worse tradeoff.)

This was NEVER software: not WindowServer, sessions, memory, or startup items.
Reboots couldn't fix it because it's hardware/connection topology.
