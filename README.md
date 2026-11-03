# Fallout New Vegas · iPhone host shim

A source port of the public Apple Silicon host that keeps its D3D9-to-Metal renderer and Win32 compatibility layer. The iPhone supplies a UIKit window, app lifecycle, a movable guest address space and native relative touch input. This is an experimental bring-your-own-game build kit with a hardware probe and separate game target. The owner confirms that build 7 reaches the menu, loads New Game and supports movement/look when the engine's existing background NavMesh setting is disabled. That build lacks audio/video output and uses the original controls. The current candidate implements native PCM/Vorbis audio, cached native movie playback, phone-aspect rendering and hybrid swipe/XInput controls. Those additions pass desktop tests but still require phone acceptance.

## Try the hardware probe first

On a Mac with Xcode 16 or newer selected and an iPhoneOS SDK, unzip the kit and run from its root:

    python3 tools/build.py probe

Output is build/FNVShimProbe.ipa, packaged for a device and ready for personal signing. From Windows, you can instead put the extracted kit's contents at the root of a new GitHub repository (keep the .github folder), open Actions → Build iPhone shim probe → Run workflow, and download the IPA artifact if the build succeeds. The workflow needs no commercial game files. Use SideStore to sign and install the probe on the iPhone. LiveContainer probe compatibility has been tested on the owner's installation; this is separate from gameplay acceptance.

A successful device run should show a colored field. Drag on the right to vary red and green. Lift and re-touch elsewhere and the colors should stay put until you move. Deflect the left thumb to vary blue independently. These changes go through the original host's simulated COM device, Clear and Present, using the Metal backend on iOS. The left stick is polled through the XInput shim. This is a graphics and input check, with no game code. An allocation failure or untranslated game entry is a diagnostic result; see the app's Documents/fnv.log. The probe only touches a small fraction of the requested 4 GiB virtual region.

## Build with a privately owned game

Use the unencrypted 32-bit PC executable and Data directory from the same installation. The developer's earlier Mac gameplay report is a reference. This kit uses source-level shims and requires compiling the translated units for the iPhone SDK.

1. Obtain the upstream static recompiler at commit ff8e0d791e3e1f0148a2245c12c7706855e66926. Set up Ghidra 12 and the upstream Python environment. Keep all work derived from the executable outside any public repository.
2. For a first translation on the Mac, use these commands with the paths set to your local values. Create a fresh Ghidra project in a writable folder. Existing full-game C generated for this exact executable is also a suitable input. Existing Mac object files cannot go into the iPhone link.

        mkdir -p "$WORK/ghidra" "$WORK/generated"
        "$HEADLESS" "$WORK/ghidra" fnv -import "$EXE"
        "$HEADLESS" "$WORK/ghidra" fnv -process "$(basename "$EXE")" -noanalysis -readOnly -scriptPath "$RECOMP/ghidra_scripts" -postScript DumpPcode.java "$WORK/all.jsonl" all
        python3 tools/translate/emit.py "$WORK/all.jsonl" "$WORK/generated"

   The basic import/export commands do not repair incomplete analysis. Follow [the maintained emitter and analysis recipe](tools/translate/README.md), including no-return/fall-through and typed computed-target analysis, before relying on a whole-game generation. Preserve the original upstream checkout. Entry counts alone do not validate behavior.

3. In the kit directory run:

        python3 tools/build_codecs.py ios --out "$WORK/codecs-ios"
        python3 tools/build.py game --generated "$WORK/generated" --exe "$EXE" --codec-prefix "$WORK/codecs-ios/prefix" --hybrid-input "$CAMERA_PROFILE_JSON"

   Output on a successful link is build/FNVGame.ipa. The builder validates pinned Ogg/Vorbis platform, architecture, source commits and file hashes, and bundles BSD licenses. It records the executable's SHA-256 for launch-time matching. Use the very same executable for translation, packaging and installation. Keep executable-specific camera profiles private. They contain a small JSON list of site/callee pairs: original CALL identity, generated callee and exact site coverage are checked before building. The game IPA contains code generated from your copy; keep it private.
4. Sideload the game IPA, launch once, then use Files to place your installation under the app's Documents/FalloutNV folder (FalloutNV.exe, Data, and game INI files). Relaunch. Keep existing saves backed up separately. Look for the first failing guest address in Documents/fnv.log if boot stops.
5. Test reaching the title screen, loading an interior, crossing into Goodsprings, firing while strafing, and a save/reload across a cold launch. The success criterion for this port is the game completing that sequence on the target phone.

## Input and platform details

The game now exposes virtual XInput controller zero: analog left stick, ABXY, shoulders, triggers, D-pad, menu/back and stick clicks. The right side sends relative mouse displacement with fractional carry; stationary/re-touched fingers do not move the camera. An explicit, verified camera-only compatibility profile selects mouse displacement/scaling while movement/buttons remain controller-driven. The old analog-input.flag is no longer required. The on-screen Aim control cycles swipe sensitivity. App suspension releases all touches and pad states and pauses native media. Physical controllers and gyro remain outside this revision.

The phone's landscape native aspect determines its preferred render resolution (long edge capped at1440). Adapter modes, Win32 metrics and generated display preference keys use that size. Existing FalloutPrefs.ini is backed up once. DirectSound PCM is mixed through AVAudioEngine; Vorbis native decoding uses marshalled 32-bit guest callbacks. Positional audio currently supplies stereo output, without a spatial renderer. Bink movie playback requires an owner-local NativeMedia/<movie-basename>.mp4 cache converted from the matching original movie. Originals remain under Data/Video; video frames return through the game's texture path. No decoder JIT or FFmpeg binary is included in the IPA. Missing caches and failed native decodes are logged explicitly.

The game loop runs on a worker thread. UIKit owns the main thread and the CAMetalLayer. The host requests 4 GiB of contiguous virtual space at an OS-selected base and uses 32-bit guest offsets. Phone build 7 has exercised archive loading, the menu and a loaded scene with movement/look; extended gameplay and memory stability remain unverified. Three 192 MiB renderer buffers remain an on-device memory concern in the game target. The diagnostic uses smaller buffers. The no-JIT build deliberately traps on missing translated entries, preserving the reason, target and guest caller. Use demonstrated patterns to improve static analysis and regenerate; a Mac-only Unicorn reference is available for discovery. The exercised startup paths use native static translation on iOS.

`FNV_TRACE_SYNC` enables periodic Present snapshots of worker/wait states, guest wait callers and recent entry history captured by each owning thread. Entry history is not a reconstructed call stack. Threads blocked before their first guest entry and pure guest loops without API boundaries require additional evidence. `FNV_TRACE_FILES` records requested/resolved paths and open errors. Both are enabled in the current game app for the loading investigation. File shims resolve existing path components case-insensitively to match Windows on the phone's case-sensitive storage.

## Repeat the host checks

For a runtime stop immediately after a returning guest helper, check the matching
Ghidra database for an incorrect no-return annotation and undecoded continuation.
`tools/ghidra/RepairCallContinuations.java` audits or repairs direct-call
continuations for explicitly supplied callee addresses. It requires an actual
RET in each selected callee's body, stays within the chosen code block, and
preserves existing instructions and defined data. Run `audit .text <callee>`
first, then `apply .text <callee>` on the private project before exporting again.
Keep executable-specific addresses and exported code outside this repository.

    bash tests/run.sh

On a Mac, `python3 tests/file_shims_case_test.py` exercises real file APIs on a case-sensitive APFS fixture. `python3 tests/sync_shims_test.py` compares actual pthread/wait behavior against the recorded pre-repair module, including wait-all signal consumption, explicit thread completion, suspended creation/resume, timeout boundaries and diagnostic snapshots. Neither test supplies original game assets or establishes gameplay success.

The media workflow runs actual PCM/DirectSound ABI, native Vorbis guest callbacks, Bink ABI, authored H264 pixel decoding and hybrid input/display checks, then compiles the public iPhoneOS host and links the macOS host. Media fixtures are authored test data. Speaker playback and touch quality require the phone.

The suite checks touch math against upstream input.c and runs a synthetic guest call sequence using the real COM table builder, gamepad state, guest heap, device creation, clear and present. It asserts the merged swipe and analog values at the renderer boundary for three frames using a headless backend. The iPhone probe uses the real Metal backend for the same call sequence.

## Sources and changes

The upstream snapshot is included under its MIT license in upstream/LICENSE. Selected host files are adapted for iOS. Recompiler and game data are external inputs. The Direct3D9 ABI table was regenerated from the public MinGW-w64 declarations using tools/d3d_table.py. The generated table contains interface slot names and x86 stack argument widths. Reference header file SHA-256 is 4fd5b2e4340046f31cfb5cc0c3f276074a205b8daf0a76583e4f3819a5f4deaf.

- Host and recompiler https://github.com/thetheoryofR/Fallout-NV-MacOS/tree/ff8e0d791e3e1f0148a2245c12c7706855e66926
- Interface declarations https://github.com/mingw-w64/mingw-w64/blob/master/mingw-w64-headers/include/d3d9.h
- macOS-to-iOS shim precedent https://github.com/zorrobyte/macos-on-ios-public
- Steam decompilation for mapping input and runtime behavior https://github.com/momusdigital/fnv_decomp
