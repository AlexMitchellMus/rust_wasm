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
if ! git -C "$SRC" apply --reverse --check "$RUST_PATCH" 2>/dev/null; then
    git -C "$SRC" apply "$RUST_PATCH"
fi
# clif-to-wasm patch.
CLIF_PATCH="$ROOT/stage-c/patches/clif-to-wasm/0001-lower-wasm-memory-grow-and-size.patch"
if ! git -C "$CLIF" apply --reverse --check "$CLIF_PATCH" 2>/dev/null; then
    git -C "$CLIF" apply "$CLIF_PATCH"
fi
# cg_clif patches (in-tree copy; stage A's wasm patch is already applied there).
for p in "$ROOT"/stage-c/patches/cg_clif/000[12]-*.patch; do
    if ! git -C "$CG" apply --reverse --check "$p" 2>/dev/null; then
        git -C "$CG" apply "$p"
    fi
done
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
    # tail of the log, where the failing command is reported.
    tail50=$(tail -n 50 "$LOG")
    if grep -q 'generate-copyright' <<< "$tail50"; then
        echo "::warning::x.py install exited $status in generate-copyright; using the rustc.wasm produced before packaging"
    else
        echo "$tail50" >&2
        echo "x.py install failed with status $status; see $LOG" >&2
        exit "$status"
    fi
fi
cp "$ART" "$OUT"
echo "rustc.wasm -> $OUT"
ls -lh "$OUT"
