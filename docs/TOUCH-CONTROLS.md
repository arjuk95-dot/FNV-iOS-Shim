# iPhone touch controls

The gameplay overlay has Fire, Aim, Interact, Jump, VATS and Pip-Boy. Movement
always floats: a new left-region touch establishes a new origin; releasing it
hides the stick and returns movement to neutral. Swipe the open right region
to look, or drag from Fire while firing. Background swipes cannot acquire Fire.

Aim defaults to toggle. Start on Aim and slide onto Fire to shoot while aiming;
lifting releases Fire and keeps toggle Aim active. Customize Controls offers
hold mode for melee blocking. Automatic weapon-type detection is not available,
so select that mode explicitly when needed.

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

Gyro starts disabled when no preference exists. Its radial toggle and preferences
persist. The editor offers aiming-only or always-in-gameplay behavior, horizontal
and vertical sensitivity/inversion, and calibration/recentering. Keep the phone
still during calibration. Gyro and touch are combined before relative-count
quantization in Direct mode. Controller response combines them before stick
clamping and discards overflow rather than queuing unwanted rotation.

Settings use the versioned `FNVTouchControls.v4` preference and safe-area-relative
positions. They do not edit game INIs or saves.

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
