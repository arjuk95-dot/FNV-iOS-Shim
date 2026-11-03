# Local translation rules

These MIT sources derive from recompiler revision
`ff8e0d791e3e1f0148a2245c12c7706855e66926`; see `../../upstream/LICENSE`.
Use this emitter for subsequent local exports. The original pinned checkout
remains available for comparison.

The maintained changes carry condition flags across all generated execution
boundaries, including secondary entries and indirect tails, and implement FXAM
classification according to Intel's instruction definition. The previous
Ghidra approximation classified infinity and NaN alike in one dispatch bit and
lost the sign of negative zero.

x87 values still use the upstream double representation. This does not emulate
all extended precision, exceptions, empty tags or rounding-status behavior.
Differential reports retain those limitations; static coverage is not a claim
of bit-exact x87 emulation.
