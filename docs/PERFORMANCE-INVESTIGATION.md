# Frame timing investigation

This diagnostic records one `[perf]` line beside the existing two-second Metal
summary. It preserves the compiler optimization level, crash tracing, settings,
rendering, shader math, audio and number of frames in flight for comparison.

| Metric | Meaning |
| --- | --- |
| `interval_ms`, `max_interval_ms` | Average and maximum elapsed time between calls to Present. Includes game logic, rendering submission and waits. |
| `main_cpu_ms` | Actual CPU time consumed by the thread running the game's frame, averaged over those intervals. Excludes time that thread sleeps or waits. Does not include worker threads. |
| `cpu_intervals`, `cpu_rejected` | Accepted CPU intervals and rejected samples. A changed presenter thread, missing clock, or CPU duration exceeding the wall interval cannot be combined into the CPU average. |
| `present_ms` | CPU wall time spent in Present, including drawable acquisition and the in-flight buffer wait. |
| `drawable_wait_ms` | Time spent acquiring a drawable; may include display or GPU backpressure. |
| `inflight_wait_ms` | Time spent waiting for an upload ring slot after submission. |
| `gpu_ms` | Average GPU execution duration of completed present command buffers, from Metal's GPU timestamps. These asynchronously completed buffers can belong to earlier frames. |
| `gpu_completed`, `gpu_unknown` | Valid and unavailable GPU timing samples. `gpu_ms=-1` means unknown, never zero-cost rendering. |
| `compile_ms_total` | Total shader/pipeline compilation time accumulated in this reporting window. It is a total, not a per-frame average. |
| `upload_peak_kib` | Maximum per-frame usage of the existing vertex/index/constant upload ring in this window. |
| `footprint_mib` | Current physical footprint of the host process, including the loaded game. `-1` means unavailable. |
| `thermal`, `low_power` | ProcessInfo thermal state (0 nominal, 1 fair, 2 serious, 3 critical), and Low Power Mode. |

Compare stable gameplay windows in the same view. Loading, menus, backgrounding,
resuming and pipeline creation must be identified separately. A large frame gap
remains visible in `max_interval_ms`; it is not silently removed from the mean.
GPU timestamps cover normal Present submissions; an explicit screenshot dump has
an additional synchronous command buffer and should be excluded from a benchmark.
Core Animation FPS may count the independent touch overlay rather than game frames.

The actual offscreen Metal pixel fixture also checks interval arithmetic, window
reset, missing/invalid GPU timestamps, the native thread CPU clock and the
production command-buffer completion handler. Successful fixture execution is
validation of the measurement path, not proof of gameplay performance.

The next controlled comparison uses `tools/build.py --no-call-trace`, exposed as
`call_trace=false` in the private build workflow. It keeps `-O1`, x86 arithmetic,
all bounded state probes, trap reporting, graphics and user settings. Only the
per-function `RT_ENTER` ring writes are omitted. The IPA records the selected
mode in `FNVGuestCallTraceEnabled`. This is a candidate until a matched phone
comparison measures its effect; the thermal state must be considered separately.
