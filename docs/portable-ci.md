# Native CI runner split

`media.yml`, `media-repair.yml`, and `texture.yml` run their portable regression
suite on Ubuntu before allocating a Mac. A failed portable suite prevents the
Apple job from starting. The Intel route invokes the repair workflow, which
owns its own Linux prerequisite, so portable tests run once on either route.
Routine media/texture workflows remain manual. The isolated\n`ci/portable-native-checks` branch has a parity-only push check for these test and\nworkflow edits; there are no cancellation changes.

## Coverage

- Media on Linux: input/null probe (`tests/run.sh`), audio mixer/DirectSound,
  MMIO archive WAV (current and historical), DirectSound lifetime (current and
  historical, including audio-to-graphics alias reproduction), Bink shim,
  input/display, touch controls, bounded guest diagnostics, calltrace equivalence.
- Texture on Linux: texture residency, lifetime and compressed-copy regressions
  (current and historical), and first-fault heap diagnostics.
- Mac retained: Objective-C/Foundation preferences, DirectShow/AVFoundation,
  native video, Metal movie rendering, native codec bridge (ARM route), UIKit
  simulator overlay (ARM route), asset catalog compilation, iPhoneOS host
  compilation, and startup host compilation (ARM route).
- Texture Mac retained: VirtualAlloc current/historical tests, which include
  Mach-dependent kernel shims, plus iPhoneOS host compilation.
- Existing private IPA, probe, startup, codec and game-host workflows are not
  part of this runner split. The duplicate game-host compile deliberately
  exercises warm object caching and is not redundant.

Every original test command is retained in its effective workflow; the
previous duplicate Linux/Mac MMIO and input checks are consolidated. No fixture,
assertion, expected historical failure, or production source was changed.

## Platform parity and limits

Run `bash tests/run_portable.sh media` and `bash tests/run_portable.sh texture`.
The standalone `portable.yml` dispatch can run the same suites on Ubuntu,
Apple Silicon macOS or Intel macOS for deliberate parity checks. Linux uses
`cc`, the existing test-only monotonic-time adapter, `libm`, and pthreads.
Darwin retains the original `xcrun clang` command, flags and libraries.

Both complete suites and all historical-failure cases passed locally on Linux
with GCC. This verifies logical regression coverage, not execution parity on
Apple Silicon: routine migrated tests no longer execute on ARM or Darwin.
Before adopting the split, compare both suites with a macOS dispatch at this
same revision. Apple-framework and iPhoneOS compilation coverage still run on
Mac for every successful media/texture dispatch. Mac execution, GitHub workflow
scheduling and actual billed-time savings cannot be validated in this Linux
workspace. Native simulator/codec/Metal behavior cannot be inferred from Linux.
