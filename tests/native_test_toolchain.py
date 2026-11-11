"""Compiler options for portable C regression harnesses (not Apple frameworks)."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPILER = ['xcrun', 'clang'] if sys.platform == 'darwin' else ['cc']
# Production host time calls use Darwin spellings; the existing Linux test shim
# maps only those calls to CLOCK_MONOTONIC, without changing production sources.
PLATFORM_FLAGS = ['-include', str(ROOT / 'tests/linux_time.h')] if sys.platform.startswith('linux') else []
LIBRARIES = ['-lm', '-pthread'] if sys.platform.startswith('linux') else []
