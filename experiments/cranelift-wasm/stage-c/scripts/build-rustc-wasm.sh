#!/usr/bin/env bash
# Build stage-c rustc.wasm: wasm32-wasip1 (non-threads), cg_clif only, with
# the stage-C rust thread/codegen patch, the cg_clif f128 and memory.grow
# patches, and the clif-to-wasm memory.grow patch.
#
# Reuses the stage-B source tree under toolchain/stage-b (incremental when the
# tree was already built). `x.py install` may fail in the final
# generate-copyright step because the patched clif-to-wasm is a path
# dependency; the rustc.wasm artifact is produced before that step and is
# copied out here. Any other failure is fatal.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)   # experiments/cranelift-wasm
TOOL="$ROOT/toolchain"
WORK="$TOOL/stage-b"
SRC="$WORK/rust"
CG="$SRC/compiler/rustc_codegen_cranelift"
CLIF="$TOOL/clif-to-wasm"
export RUSTUP_HOME="${RUSTUP_HOME:-$TOOL/rustup}"
export CARGO_HOME="${CARGO_HOME:-$TOOL/cargo}"
export PATH="$CARGO_HOME/bin:$PATH"
export RUSTUP_TOOLCHAIN=nightly-2026-10-19
WASI_SDK="$WORK/wasi-sdk"
OUT="$TOOL/stage-c/artifacts/rustc.wasm"
LOG="$ROOT/stage-c/results/build-rustc-wasm.log"

jobs() {
    if [ -n "${BUILD_JOBS:-}" ]; then
        printf '%s' "$BUILD_JOBS"
    elif command -v nproc >/dev/null 2>&1; then
        nproc
    else
        sysctl -n hw.ncpu
    fi
}
JOBS=$(jobs)

[ -d "$SRC/.git" ] || { echo "missing stage-B rust tree; run stage-b/scripts/build-rustc-wasm.sh once" >&2; exit 1; }
[ -d "$WASI_SDK" ] || { echo "missing $WASI_SDK" >&2; exit 1; }
[ -d "$CLIF/.git" ] || { echo "missing $CLIF; run ci/setup-toolchain.sh first" >&2; exit 1; }
mkdir -p "$(dirname "$LOG")" "$(dirname "$OUT")"

# Rust thread/codegen patch. It may be applied as a commit (the local
# experiment tree) or left uncommitted (a fresh CI checkout); the reverse
# check covers both and makes reruns idempotent.
RUST_PATCH="$ROOT/stage-c/patches/rust/0001-wasm-run-compiler-and-codegen-on-calling-thread.patch"
if git -C "$SRC" apply --reverse --check "$RUST_PATCH" 2>/dev/null; then
    echo "rust patch already applied"
else
    echo "applying $(basename "$RUST_PATCH")"
    git -C "$SRC" apply "$RUST_PATCH"
fi
git -C "$SRC" apply --reverse --check "$RUST_PATCH" || {
    echo "rust patch is not present after apply" >&2; exit 1; }

# clif-to-wasm patch (this checkout is the repository root, so the patch's
# src/... paths resolve correctly).
CLIF_PATCH="$ROOT/stage-c/patches/clif-to-wasm/0001-lower-wasm-memory-grow-and-size.patch"
if git -C "$CLIF" apply --reverse --check "$CLIF_PATCH" 2>/dev/null; then
    echo "clif-to-wasm patch already applied"
else
    echo "applying $(basename "$CLIF_PATCH")"
    git -C "$CLIF" apply "$CLIF_PATCH"
fi
git -C "$CLIF" apply --reverse --check "$CLIF_PATCH" || {
    echo "clif-to-wasm patch is not present after apply" >&2; exit 1; }

# cg_clif patches (in-tree copy; stage A's wasm patch is already applied there).
# The patch paths are src/... relative to the *rust* repository root, not to
# the cg_clif directory. Running `git -C "$CG" apply` here silently reports
# "Skipped patch" and exits 0 because the path is outside the current
# directory, which left a fresh CI tree unpatched. Apply with --directory from
# the root instead, then assert the content is really there.
CG_PREFIX=compiler/rustc_codegen_cranelift
for p in "$ROOT"/stage-c/patches/cg_clif/000[12]-*.patch; do
    if git -C "$SRC" apply --reverse --check --directory="$CG_PREFIX" "$p" 2>/dev/null; then
        echo "$(basename "$p") already applied"
    else
        echo "applying $(basename "$p")"
        git -C "$SRC" apply --directory="$CG_PREFIX" "$p"
    fi
    git -C "$SRC" apply --reverse --check --directory="$CG_PREFIX" "$p" || {
        echo "$(basename "$p") is not present after apply" >&2; exit 1; }
done
grep -q 'llvm.wasm.memory.grow.i32' "$CG/src/intrinsics/llvm.rs" || {
    echo "cg_clif memory.grow lowering missing from $CG/src/intrinsics/llvm.rs" >&2; exit 1; }
grep -q 'pub enum WasmIntrinsic' "$CLIF/src/wasm_intrinsic.rs" || {
    echo "clif-to-wasm WasmIntrinsic missing from $CLIF/src/wasm_intrinsic.rs" >&2; exit 1; }
# The in-tree cg_clif must consume the patched clif-to-wasm, not crates.io.
# Fail loudly if the pinned Cargo.toml line changes: a silent no-op would use
# the crates.io release without the memory.grow patch.
python3 - "$CG/Cargo.toml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'clif-to-wasm = { version = "0.3.0", features = ["module"] }'
new = 'clif-to-wasm = { path = "../../../../clif-to-wasm", features = ["module"] }'
if new in s:
    pass
elif old in s:
    s = s.replace(old, new)
    open(p, 'w').write(s)
else:
    sys.exit(f"unexpected clif-to-wasm dependency in {p}; cannot point it at the patched checkout")
PY

sed "s|@WASI_SDK@|$WASI_SDK|g" "$ROOT/stage-c/bootstrap.toml" > "$SRC/bootstrap.toml"
cd "$SRC"
# On GitHub Actions bootstrap assumes HEAD^1 is an upstream rust-lang/rust
# commit. Here HEAD is the last of the 23 prior-art commits applied with
# `git am` (whose hashes differ from upstream because the committer timestamp
# differs), so download-ci-llvm asks for a nonexistent artifact and 404s.
# --ci=false uses the local freshness logic, which walks back to the pinned
# upstream commit b6eeb93 before downloading LLVM.
set +e
./x.py install --ci=false --set build.jobs="$JOBS" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
set -e

ART="$SRC/build/wasm32-wasip1/stage2/bin/rustc.wasm"
[ -f "$ART" ] || { echo "rustc.wasm was not produced; see $LOG" >&2; exit 1; }
if [ "$status" -ne 0 ]; then
    # The known packaging quirk is the last generate-copyright step. Do not
    # hide a real compile/link failure behind a stale artifact: look at the
    # tail of the log, where the failing command is reported. CI's backtrace
    # is longer than macOS's and ends with `run::GenerateCopyright`, so use a
    # case-insensitive match over a wide tail.
    tail200=$(tail -n 200 "$LOG")
    if grep -qi 'generate-copyright' <<< "$tail200"; then
        echo "::warning::x.py install exited $status in generate-copyright; using the rustc.wasm produced before packaging"
    else
        echo "$tail200" >&2
        echo "x.py install failed with status $status; see $LOG" >&2
        exit "$status"
    fi
fi
cp "$ART" "$OUT"
echo "rustc.wasm -> $OUT"
ls -lh "$OUT"
