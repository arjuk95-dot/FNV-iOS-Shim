#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
h=upstream/recomp/host
cc -std=gnu11 -Iios -I"$h" tests/input_test.c "$h/input.c" -lm -pthread -o "$out/input"
"$out/input"
cc -std=gnu11 -Iios -I"$h" -include tests/linux_time.h tests/null_probe.c ios/{FNVPad,FNVDisplay,FNVProbe,ProbeRuntime}.c "$h"/{d3d9,d3d9_null,dinput,gheap,input,com}.c -lm -pthread -o "$out/probe"
"$out/probe"
