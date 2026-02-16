# Known SH2 Compiler Issues

This file tracks confirmed codegen risks in the current `sh2eb-elf-gcc` toolchain used in this repo.

## Environment

- Host validation target: macOS arm64
- Toolchain under test: `sh2eb-elf-gcc (GCC) 14.3.0`, `binutils 2.44`
- Optimization levels checked: `-O0/-O1/-O2/-O3`, plus `-Os` for PR122948

## PR122227: volatile unaligned store emits spurious loads

- Tracker: <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=122227>
- Observed on current toolchain: **yes**
- Severity: **Medium** (can be **High** for MMIO registers where reads have side effects)

### What happens

For volatile stores through potentially unaligned objects (for example via `volatile unsigned char[]`), optimized SH2 codegen can perform read-modify-write style byte accesses (spurious loads before stores), instead of pure write sequences.

### Practical impact

- Reads from write-only or side-effect registers can break hardware behavior.
- `__builtin_assume_aligned` on the pointer expression is not reliable mitigation in this pattern.

### Mitigation strategies

1. Define MMIO/register objects with explicit alignment (`__attribute__((aligned(4)))`) and correct typed volatile pointers.
2. Avoid volatile writes via byte-array alias patterns for register access.
3. Add code review rule: no volatile register writes through unknown alignment.
4. Keep this risk in mind when enabling high optimization levels for low-level drivers.

## PR122948: SH comparison miscompile (`subc` carry/T-flag logic)

- Tracker: <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=122948>
- Observed on current toolchain: **yes**
- Severity: **Critical** (silent wrong-code in optimized builds)

### What happens

Expressions like:

```c
if (b - a - 1 <= b) ...
```

can compile to a broken `sett/subc` sequence on SH, producing incorrect branch behavior at `-O1/-O2/-Os`.

### Practical impact

- Functional misbehavior without compile-time errors.
- Affects arithmetic/compare-heavy code and potentially control-flow correctness.

### Mitigation strategies (until patched)

1. Avoid this expression shape in critical code paths (`b - a - 1 <= b` and equivalent transforms).
2. Consider targeted source rewrites that avoid problematic carry-based lowering patterns.
3. Add regression tests for known problematic arithmetic compares in CI.
4. Prioritize backport/fix work for this issue before treating toolchain as production-stable for broad SH code.

## Validation policy recommendation

When changing GCC version, SH backend patches, or optimization flags:

1. Re-run `./smoke-test-sh2eb.sh`.
2. Re-run dedicated codegen checks for PR122227 and PR122948 patterns.
3. Record results in this file (status/versions/date).
