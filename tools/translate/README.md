# Local translation rules

These MIT sources derive from recompiler revision
`ff8e0d791e3e1f0148a2245c12c7706855e66926`; see `../../upstream/LICENSE`.
Use this emitter for subsequent local exports. The original pinned checkout
remains available for comparison.

The maintained changes carry condition flags across all generated execution
boundaries, including secondary entries and indirect tails, and implement FXAM
classification according to [Intel's instruction definition](https://cdrdv2-public.intel.com/812383/253666-sdm-vol-2a.pdf). The previous
Ghidra approximation classified infinity and NaN alike in one dispatch bit and
lost the sign of negative zero.

x87 values still use the upstream double representation. This does not emulate
all extended precision, exceptions, empty tags or rounding-status behavior.
Differential reports retain those limitations; static coverage is not a claim
of bit-exact x87 emulation.

## Regeneration and acceptance

Keep the original executable, Ghidra projects, P-code, generated C, snapshots and
test fixtures outside Git. Check executable identity before exporting or building.
Work on a separate analysis project so earlier evidence remains available.

1. Run the pinned `FixNoReturn`, `ResolveJumpTables` and `FixEntries` preparation
   passes, and audit returning-call continuations and dispatch coverage. Repeat
   preparation until the newly recovered code has also been inspected.
2. Run `ResolveCrtOperationTables.java` first in `audit`, then `apply` mode on
   the working project. Export after the proven computed-flow edges are present.
   Merge its secondary-entry output with `FixEntries` output.
3. Generate with this maintained emitter, recording its identity:

   ```sh
   python3 tools/translate/emit.py /private/all.jsonl /private/generated --extra /private/merged-extra-entries.json
   python3 tools/game_inputs.py pack --generated /private/generated --exe /private/FalloutNV.exe --generator tools/translate/emit.py --out /private/fnv-game-inputs.zip
   ```

4. Use `startup.yml` for strict native execution, a separate optional Mac
   discovery reference and selected original-x86 differential comparisons.
   Optional `--fixtures` on the pack command adds a small diagnostic caller-state
   manifest. Validate its original-x86 states before comparing native execution.
   Keep invalid reference trials, flag differences, numerical differences and
   unexercised paths explicit. New entry counts and successful links are not
   behavioral acceptance.
5. Build the iPhone IPA only after assessing desktop stops. A fixture with no
   game assets cannot establish menu or gameplay behavior. Record device results
   separately: installed source/data-container identity, first Present, responsive
   menu, loaded game, player movement and look.

Treat every missing destination as evidence for a rule investigation: retain the
guest target, incoming transfer/caller, original instructions and the analysis
reason it was missed. Check other instances before shipping a rule change.
Neither the Mac reference engine nor the differential runtime is linked into iOS.
