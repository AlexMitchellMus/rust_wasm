#!/usr/bin/env bash
# Build stage-c rustc.wasm: wasm32-wasip1 (non-threads), cg_clif only, with
# the stage-C rust thread/codegen patch, the cg_clif f128 and memory.grow
# patches, and the clif-to-wasm memory.grow patch.
#
# Reuses the stage-B source/build tree under toolchain/stage-b (incremental).
# `x.py install` may fail in the final generate-copyright step because the
# patched clif-to-wasm is a path dependency; the rustc.wasm artifact is
# produced before that step and is copied out here.
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

[ -d "$SRC/.git" ] || { echo "missing stage-B rust tree; run stage-b/scripts/build-rustc-wasm.sh once" >&2; exit 1; }
[ -d "$WASI_SDK" ] || { echo "missing $WASI_SDK" >&2; exit 1; }

# Rust thread/codegen patch (already committed in this experiment's tree).
if ! git -C "$SRC" log --oneline -n 50 | grep -q 'run compiler and codegen on the calling thread'; then
    git -C "$SRC" apply "$ROOT/stage-c/patches/rust/0001-wasm-run-compiler-and-codegen-on-calling-thread.patch"
fi
# clif-to-wasm patch.
if ! git -C "$CLIF" apply --reverse --check "$ROOT/stage-c/patches/clif-to-wasm/0001-lower-wasm-memory-grow-and-size.patch" 2>/dev/null; then
    git -C "$CLIF" apply "$ROOT/stage-c/patches/clif-to-wasm/0001-lower-wasm-memory-grow-and-size.patch"
fi
# cg_clif patches (in-tree copy; stage A's wasm patch is already applied there).
for p in "$ROOT"/stage-c/patches/cg_clif/000[12]-*.patch; do
    if ! git -C "$CG" apply --reverse --check "$p" 2>/dev/null; then
        git -C "$CG" apply "$p"
    fi
done
# The in-tree cg_clif must consume the patched clif-to-wasm, not crates.io.
python3 - "$CG/Cargo.toml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('clif-to-wasm = { version = "0.3.0", features = ["module"] }',
            'clif-to-wasm = { path = "../../../../clif-to-wasm", features = ["module"] }')
open(p,'w').write(s)
PY

sed "s|@WASI_SDK@|$WASI_SDK|g" "$ROOT/stage-c/bootstrap.toml" > "$SRC/bootstrap.toml"
cd "$SRC"
set +e
./x.py install --set build.jobs="${BUILD_JOBS:-12}" 2>&1 | tee "$ROOT/stage-c/results/build-rustc-wasm.log"
set -e
ART="$SRC/build/wasm32-wasip1/stage2/bin/rustc.wasm"
[ -f "$ART" ] || { echo "rustc.wasm was not produced; see stage-c/results/build-rustc-wasm.log" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
cp "$ART" "$OUT"
echo "rustc.wasm -> $OUT"
ls -lh "$OUT"
