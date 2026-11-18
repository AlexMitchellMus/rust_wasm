#!/usr/bin/env bash
# Stage B driver: rustc.wasm (cg_clif only) under Wasmtime, native Wild as the
# linker, then run plugin (c).
#
#   ./run.sh build     build the Wasmtime host (rustc.wasm/sysroot assumed built)
#   ./run.sh sysroot   rebuild the matching stage1 sysroot
#   ./run.sh check     compile plugin (c) with rustc.wasm, link with Wild, eval
#   ./run.sh bench     N warm compile+eval runs plus cold/cached module timings
#   ./run.sh inspect   validate rustc.wasm and scan for LLVM symbols
#   ./run.sh all       build + check + bench
#
# Everything downloaded/built lives under ../toolchain/ (gitignored).
set -euo pipefail

STAGE_B=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAGE_A=$(cd "$STAGE_B/.." && pwd)
TOOL="$STAGE_A/toolchain"
WORK="$TOOL/stage-b"
RUSTC_WASM="$WORK/artifacts/rustc.wasm"
SYSROOT="$WORK/sysroot-stage1"
SRC="$STAGE_A/programs/c_plugin/src/lib.rs"
LINKER="$TOOL/target/wild/release/wild"
HOST="$TOOL/target/stage-b-host/release/stage-b-host"
OUT="$WORK/work/c_plugin.wasm"

export RUSTUP_HOME="${RUSTUP_HOME:-$TOOL/rustup}"
export CARGO_HOME="${CARGO_HOME:-$TOOL/cargo}"
export PATH="$CARGO_HOME/bin:$PATH"
export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-1.99.1}"

log() { printf '\n== %s\n' "$*" >&2; }

build_host() {
    log "building stage-b host (Wasmtime 46.0.3 + wasmtime-wasi-threads)"
    ( cd "$STAGE_B/host" && CARGO_TARGET_DIR="$TOOL/target/stage-b-host" \
        cargo build --release )
}

need_rustc() {
    [ -x "$RUSTC_WASM" ] || {
        echo "missing $RUSTC_WASM; run stage-b/scripts/build-rustc-wasm.sh first" >&2
        exit 1
    }
}

need_sysroot() {
    [ -d "$SYSROOT/lib/rustlib/wasm32-unknown-unknown/lib" ] || {
        echo "missing stage1 sysroot; running scripts/build-plugin-sysroot.sh stage1" >&2
        "$STAGE_B/scripts/build-plugin-sysroot.sh" stage1
    }
}

case "${1:-all}" in
    build) build_host ;;
    sysroot)
        "$STAGE_B/scripts/build-plugin-sysroot.sh" stage1
        ;;
    check)
        need_rustc; need_sysroot; build_host
        mkdir -p "$WORK/work"
        "$HOST" check --rustc "$RUSTC_WASM" --sysroot "$SYSROOT" \
            --src "$SRC" --linker "$LINKER" --work "$WORK/work" --out "$OUT" \
            --cache-dir "$WORK/cache"
        ;;
    bench)
        need_rustc; need_sysroot; build_host
        mkdir -p "$WORK/work-bench" "$STAGE_B/results"
        "$HOST" bench --rustc "$RUSTC_WASM" --sysroot "$SYSROOT" \
            --src "$SRC" --linker "$LINKER" --work "$WORK/work-bench" --out "$OUT" \
            --cache-dir "$WORK/cache" --runs 5 \
            --json "$STAGE_B/results/stage-b.json"
        ;;
    inspect)
        need_rustc; build_host
        "$HOST" inspect --wasm "$RUSTC_WASM"
        ;;
    all)
        need_rustc; need_sysroot; build_host
        "$0" check
        "$0" bench
        ;;
    *)
        echo "usage: $0 [build|sysroot|check|bench|inspect|all]" >&2
        exit 1
        ;;
esac
