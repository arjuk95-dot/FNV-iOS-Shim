# Translation behavior checks

`rt_test.c` and `difftest.py` originate in the pinned MIT upstream recompiler;
see `upstream/LICENSE`. The native test library reuses the translated objects
but excludes host shims. Original x86 executes independently in Unicorn.
Register metadata is a small subset of the generic Ghidra x86 processor register
layout, with no executable-derived instructions or data.

The sampled entries are supplied privately through the workflow input. Trials
compare general registers, logical x87 ST0, XMM registers, flags and guest memory.
Unicorn faults and exhausted reference budgets are reported as invalid fixtures,
not passes. Pure pop/stack-adjust/return secondary entries get a return slot
derived from their original bytes; this states the caller-frame precondition
instead of treating every interior label as a normal function entry.
An optional private fixture manifest supplies inspected caller preconditions for
bounded lookup, string and memory operations. `-` as the library checks only that
the original x86 fixtures complete; its `reference-valid` result is not a native
translation pass. Invalid trials remain listed in the report.

`replay_math_snapshot.py` additionally starts the repaired operation dispatcher
from captured guest registers/stack/frame/TEB, testing the recorded argument and
derived finite/zero/infinity/NaN input classes. Both sides get the same original
PE initial globals. This controlled fixture is not a full runtime replay. The
report retains flag and written-memory differences even when general registers
and the mathematical result match; these differences require review before a
claim of correctness. A mismatch or no valid comparison fails the replay step.
The separate `--whole-wrapper` test validates the original wrapper prologue and
reconstructs its incoming frame from the snapshot, then compares its completed
return. Absolute and ULP error are reported without silently allowing a tolerance.

The Mac reference is diagnostic only. Neither Unicorn nor this test runtime is
linked into the iPhone application.
