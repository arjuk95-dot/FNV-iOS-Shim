# Startup diagnostics

The iPhone kit compiles guest code ahead of time. Unlike the pinned upstream
macOS host, it does not include the Unicorn fallback for addresses absent from
the static dispatch table. A translation gap therefore stops execution. Host
return code 3 groups guest traps together; the log contains the real reason.

Run `AuditTranslationCoverage.java` on the exact executable's Ghidra project
with a line-separated list of compiled guest addresses, an output JSON path,
and a private output TSV path. This read-only census identifies unresolved
branches, missing direct-call dispatch targets and undecoded continuations.
Its counts do not prove those sites are reached or that all code is covered.

`startup_build.py` links the same dispatcher and host shims into a native macOS
CLI with the null renderer. First run `--host-check --out build/startup` without
private inputs to validate the diagnostic host itself. With private generated
sources, use `--generated <directory> --out build/startup`, then run:

    python3 tools/run_startup.py build/startup/fnv-startup <exact-executable> --out build/diagnostics

The `startup.yml` workflow runs these checks on the existing Mac runner. A
translation trap fails the diagnostic and records the precise stop. No game
Data is uploaded. This can reveal startup gaps before another iPhone install;
it cannot establish title-screen boot, iPhone graphics or gameplay. An exit or
timeout caused by missing game files must be investigated separately.

The pinned upstream also supplies `FixNoReturn.java`, `ResolveJumpTables.java`
and `FixEntries.java`. Use them on a private working project, inspect their
results and re-export before testing. Their completion is not a substitute for
executing the translated startup path.
