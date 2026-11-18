#!/usr/bin/env bash
# Stage C driver: rustc.wasm on wasm32-wasip1 (no wasi-threads), pure
# rustc.wasm-built plugin sysroot, growable plugin heap, latest Wasmtime.
#
#   ./run.sh check      compile + link + eval plugin (c) against the pure sysroot
#   ./run.sh plugins    build (a),(b),(c),(e),(f) with rustc.wasm (strict)
#   ./run.sh bench      stage-B table on latest Wasmtime (median of 5)
#   ./run.sh a2         A.2 runtime/load measurements for (e),(f)
set -euo pipefail
STAGE_C=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$STAGE_C/.." && pwd)
TOOL="$ROOT/toolchain"
RUSTC_WASM="$TOOL/stage-c/artifacts/rustc.wasm"
PURE="$TOOL/stage-c/sysroot-pure"
HOST="$TOOL/target/stage-c-host/release/stage-c-host"
WILD="$TOOL/target/wild/release/wild"
export RUSTUP_HOME="${RUSTUP_HOME:-$TOOL/rustup}"
export CARGO_HOME="${CARGO_HOME:-$TOOL/cargo}"
# rust-objcopy for libm's build script.
export PATH="$RUSTUP_HOME/toolchains/nightly-2026-10-19-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/bin:$CARGO_HOME/bin:$PATH"
export RUSTUP_TOOLCHAIN=nightly-2026-10-19
export RUSTC="$STAGE_C/scripts/rustc-wasm-wrapper.sh"
export STAGE_C_SYSROOT="$PURE"
export STAGE_C_RUSTC_WASM="$RUSTC_WASM"
export STAGE_C_HOST="$HOST"
export STAGE_C_WILD="$WILD"
export CG_CLIF_WASM_STRICT=1
export CARGO_TARGET_DIR="$TOOL/target/stage-c-pure-wasm"

need() { [ -e "$1" ] || { echo "missing $1" >&2; exit 1; }; }

case "${1:-check}" in
    plugins)
        need "$RUSTC_WASM"; need "$PURE"
        for p in a_add b_alloc c_plugin e_math f_geometry; do
            echo "== $p (rustc.wasm, strict)"
            ( cd "$STAGE_C/programs/$p" && RUSTFLAGS="-Cpanic=abort" \
                cargo build --release --target wasm32-unknown-unknown )
        done
        ;;
    check)
        need "$RUSTC_WASM"; need "$PURE"
        mkdir -p "$TOOL/stage-c/work"
        "$HOST" check --rustc "$RUSTC_WASM" --sysroot "$PURE" \
            --src "$STAGE_C/programs/c_plugin/src/lib.rs" --linker "$WILD" \
            --work "$TOOL/stage-c/work" --out "$TOOL/stage-c/work/c_plugin.wasm" \
            --cache-dir "$TOOL/stage-c/cache"
        ;;
    bench)
        need "$RUSTC_WASM"; need "$PURE"
        mkdir -p "$TOOL/stage-c/work-bench" "$STAGE_C/results"
        "$HOST" bench --rustc "$RUSTC_WASM" --sysroot "$PURE" \
            --src "$STAGE_C/programs/c_plugin/src/lib.rs" --linker "$WILD" \
            --work "$TOOL/stage-c/work-bench" --out "$TOOL/stage-c/work-bench/c_plugin.wasm" \
            --cache-dir "$TOOL/stage-c/cache" --runs 5 \
            --json "$STAGE_C/results/stage-c.json"
        ;;
    a2)
        need "$PURE"
        H="$TOOL/target/a2/harness/release/a2-harness"
        [ -x "$H" ] || ( cd "$ROOT/stage-b/a2/harness" && \
            CARGO_TARGET_DIR="$TOOL/target/a2/harness" cargo build --release )
        P="$CARGO_TARGET_DIR/wasm32-unknown-unknown/release"
        for p in e_math f_geometry; do
            "$H" inspect "$P/$p.wasm"
            "$H" load "$P/$p.wasm"
        done
        "$H" bench_math "$P/e_math.wasm" 100000 5
        "$H" bench_geom "$P/f_geometry.wasm" 40000 5
        ;;
    *)
        echo "usage: $0 [plugins|check|bench|a2]" >&2
        exit 1
        ;;
esac
