# iPhone touch controls

The gameplay overlay has Fire, Aim, Interact, Jump, VATS and Pip-Boy. Movement
always floats: a new left-region touch establishes a new origin; releasing it
hides the stick and returns movement to neutral. Swipe the open right region
to look, or drag from Fire while firing. Background swipes cannot acquire Fire.

Tap **Aim / Gyro** during regular gameplay to enable or disable gyro, independently
of aiming down sights (ADS). Hold it for 0.32 seconds to enter ADS; lifting your
finger keeps ADS active. The next tap exits ADS without changing gyro. Once out
of ADS, taps toggle gyro again. The button shows **Gyro ON**, **Gyro OFF** or
**Exit ADS** so you can see which action a tap will take.

You can also start on Aim and slide onto Fire to aim and shoot immediately.
Lifting stops Fire and keeps ADS active. The hold delay is adjustable in Customize
Controls. A cancelled touch or release outside Aim does not toggle gyro.
ADS sends the game's normal Aim / melee-block binding.

Tap Pip-Boy for a normal press. Hold it for the local utility radial; this consumes
the gesture without sending a Pip-Boy/light hold to the game. Slide and release
on a sector to select it; the center and outside cancel. Weapons and More remain
open for a subsequent touch. Local radials and the editor do not pause the game.

The seven weapon directions use the game's existing hotkey assignments. Pure
D-pad Up stays reserved for changing ammunition. More includes holster/ready,
light, grab/drop, wait, pause and customization. Gameplay action bindings are
sampled from the game's current controller mapping.

## Customization and gyro

Choose **More → Customize Controls**. Select Gameplay or Pip-Boy, then a control
or region. Preview lets you drag it. Size, opacity, visibility and labels can be
changed independently. Movement/look regions, stick response, swipe sensitivity,
ADS multiplier, Fire-drag sensitivity and radial placement/order are adjustable.
Apply saves; Cancel restores the settings present when the editor opened.
Reset Selected and Reset Layout recover defaults. Hidden controls stay in the
selection list. Holding four fingers for 1.2 seconds recovers the editor even
if the Pip-Boy button has been hidden.

Gyro starts disabled when no preference exists. Aim's tap, the radial toggle and
the editor control the same saved preference. When enabled, gyro works throughout
gameplay, both in and out of ADS; it stays off in game menus. The editor offers
horizontal and vertical sensitivity/inversion, and calibration/recentering. Keep
the phone still during explicit calibration. Toggling gyro does not recalibrate
against a moving phone. Gyro and touch are combined before relative-count
quantization in Direct mode. Controller response combines them before stick
clamping and discards overflow rather than queuing unwanted rotation.

Settings use the versioned `FNVTouchControls.v6` preference and safe-area-relative
positions. Existing layouts, sensitivity values, gyro state and utility assignments
migrate automatically. The older preference remains available for rollback.
The old hold-only ADS and aiming-only gyro options are replaced by the gestures
above. Game INIs and saves are not edited.

## Move actions between Radial and More

Choose **Customize Controls → Utilities**. Each of the seven radial sectors and
six More entries has an action chooser. Choosing an action swaps it with the
selected slot, including across the two menus. You can put Holster, Light, Wait,
Pause or Customize Controls on the radial, or move Reload, Change Ammo, Camera,
Gyro and Weapons into More. Reorder either list the same way. Apply saves both
lists; Cancel restores both. **Reset Utilities** restores only utility assignments,
placement and hold timing.

The default radial is Reload, Crouch, Weapons, **Holster / Ready**, Camera View,
Gyro and More. Change Ammo is in More. Existing pre-v5 radial ordering is retained
with Holster replacing Change Ammo in its previous sector. Other control positions
and sensitivities are retained, and earlier preference versions remain available
for rollback.

More's navigation entry stays on the radial and can move between radial sectors.
Its popup always has Back. This keeps every action reachable while rearranging.
Hold durations and native gamepad bindings belong to the action and follow it
between menus. Gyro's visible state and the persistent Weapons submenu work from
either location. The Utilities tab's Preview shows the current radial and lets you
drag it into position without executing game actions.

## Classic swipe and gyro baseline

Direct swipe look defaults to the previous **Aim 3x** response: each UIKit point
produces three relative mouse counts. This retains the full distance of a fast
swipe instead of imposing the original game's controller turn-rate limit.
Movement, actions, menu controls and physical controllers continue to use XInput.
The four existing verified camera-only compatibility sites select the relative
path for touch; an active physical controller retains its original camera path.

Gyro defaults to a 3x camera/device rotation ratio before the game's own zoom.
Its counts are calibrated from the live original mouse sensitivity. The common
Look multiplier and the Aiming multiplier affect both swipe and gyro; per-axis
gyro multipliers extend to 20x. Existing custom gyro values, inversion, layouts
and controller calibration are preserved on migration. Old default smoothing is
removed; optional direction smoothing preserves distance and stops immediately.

Direct swipe can be disabled for controller-style response. Its calibration
controls are grouped separately. Touch camera motion has independent ownership;
menus, cancellation, backgrounding and controller takeover clear its pending
state and buffered events while retaining input from other sources.

## Context controls

### Standard controller fallback

**Double-tap with three fingers** anywhere on the game view to switch to a
standard XInput overlay. Repeat the gesture to return to the normal touch layout.
This works in gameplay, menus, utility wheels and the editor, even when custom
controls are hidden. In the editor it cancels uncommitted changes.

The fallback exposes both floating analog sticks, D-pad, A/B/X/Y, LT/RT, LB/RB,
L3/R3, Start and Back. These send raw controller inputs independently of menu
detection and gameplay remapping. Hold a button to hold its controller input;
release it to stop. The right stick is a held analog stick rather than swipe look.
Gyro and gameplay aim toggles are suspended. A visible Standard XInput label shows
the active mode. Menu changes and backgrounding retain that mode while releasing
old touch inputs. A cold launch starts with the normal layout.

Switching modes releases touch-owned buttons, both sticks and pending camera
motion. Saved layouts, sensitivity settings and physical-controller input are
preserved. The normal generic menu layout also exposes LT and RT for screens such
as the Vigor Tester that use additional controller navigation.

### Automatic layouts

Actual guest menu visibility selects the layout, including when a physical
controller opens a menu. Entering a menu releases touch-owned combat and camera
state before returning its first input snapshot. Existing fingers are quarantined
until a fresh touch. Physical-controller contributions have separate ownership.

| Context | Inputs |
| --- | --- |
| Pip-Boy | LT/RT previous/next section; navigation, A confirm/use, B back/close, X/Y item actions |
| VATS | Left stick body parts; right stick targets; RT queue, A confirm, B cancel, X/Y special actions |
| Lockpick | Left horizontal axis pin angle; right horizontal axis cylinder; X force, B exit |
| Hacking/terminal | Direction buttons, A select, B exit |

On Local and World Map pages, the right region is a floating **map pan stick**:
touch it, drag from that origin, and hold to keep moving the map. Release to stop.
The left region is vertical-only zoom; dragging sideways cannot switch Data tabs.
The on-screen Zoom + / Zoom − buttons send native RB / LB. Previous/Next Tab uses
D-pad left/right to cycle Local Map, World Map, Quests, Notes and Radio.

Use **Select / Travel** on a highlighted discovered World Map destination, then
confirm with a fresh Confirm press. Back cancels. The original game's fast-travel
restrictions still apply. Place Marker sends X. The fast-travel confirmation takes
priority over the map context and releases both sticks before accepting new input.
Stats/Items and the other Data pages keep normal Pip-Boy navigation and section controls.

Landscape changes, backgrounding, cancellation, modal transitions and controller
takeover clear this overlay's transient inputs. Maximum-turn-rate, dead-zone and
response calibration account for the game's controller camera behavior; actual
touch and gyro feel still needs a phone test.

## Validation boundary

`tests/touch_controls_test.py` runs production input ownership and gesture/math
policy; `tests/input_display_test.py` exercises the actual XInput shim with native
menu-memory and binding fixtures. These do not establish UIKit, sensor or physical
controller acceptance. Apple compilation, screenshots and phone checks are tracked
in the project work-order receipts and must be reported separately.
