#!/bin/bash
# Same suite on Linux by default, or macOS for deliberate parity verification.
set -eu
cd "$(dirname "$0")/.."
case "${1:-}" in
  media)
    bash tests/run.sh
    python3 tests/audio_shims_test.py
    python3 tests/mmio_ioproc_test.py --reference
    python3 tests/mmio_ioproc_test.py
    python3 tests/dsound_lifetime_test.py --reference
    python3 tests/dsound_lifetime_test.py
    python3 tests/bink_shims_test.py
    python3 tests/input_display_test.py
    python3 tests/touch_controls_test.py
    python3 tests/guest_diagnostics_test.py
    python3 tests/calltrace_equivalence_test.py
    ;;
  texture)
    python3 tests/texture_residency_test.py
    python3 tests/texture_lifetime_test.py --reference
    python3 tests/texture_copy_test.py --reference
    python3 tests/texture_lifetime_test.py
    python3 tests/texture_copy_test.py
    python3 tests/heap_diagnostics_test.py
    ;;
  *) echo "Usage: $0 {media|texture}" >&2; exit 2 ;;
esac
