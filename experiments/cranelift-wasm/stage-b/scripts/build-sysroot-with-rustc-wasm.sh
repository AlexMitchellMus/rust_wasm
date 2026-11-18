#!/usr/bin/env bash
# Optional: build the wasm32-unknown-unknown core/alloc/compiler_builtins
# sysroot with rustc.wasm itself (cg_clif), via a Cargo RUSTC wrapper. This
# makes the plugin sysroot pure-Rust and guarantees its metadata matches
# rustc.wasm. Slower than the stage1 fallback; not used by run.sh by default.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL="$ROOT/toolchain"
WORK="$TOOL/stage-b"
SYS="$WORK/sysroot-wasm"
TARGET="$TOOL/target/stage-b-sysroot-wasm"
export RUSTUP_HOME="${RUSTUP_HOME:-$TOOL/rustup}"
export CARGO_HOME="${CARGO_HOME:-$TOOL/cargo}"
export PATH="$CARGO_HOME/bin:$RUSTUP_HOME/toolchains/nightly-2026-10-19-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/bin:$PATH"
export RUSTUP_TOOLCHAIN=nightly-2026-10-19
export STAGE_B_HOST="$TOOL/target/stage-b-host/release/stage-b-host"
export STAGE_B_RUSTC_WASM="$WORK/artifacts/rustc.wasm"
export STAGE_B_WILD="$TOOL/target/wild/release/wild"
export STAGE_B_STAGE1="$WORK/rust/build/host/stage1/bin/rustc"
export STAGE_B_CACHE="$WORK/cache"
export STAGE_B_STD_SRC="$WORK/rust/build/aarch64-apple-darwin/stage1/lib/rustlib/src/rust"
export STAGE_B_REAL_SRC="$WORK/rust"
export RUSTC="$ROOT/stage-b/scripts/rustc-wasm-wrapper.sh"
export RUSTC_BOOTSTRAP=1
rm -rf "$TARGET" "$SYS"
mkdir -p "$SYS/lib/rustlib/wasm32-unknown-unknown/lib"
cd "$ROOT/programs/c_plugin"
RUSTFLAGS="-Cpanic=abort -Zmir-opt-level=4" CARGO_TARGET_DIR="$TARGET" \
    cargo build --release --target wasm32-unknown-unknown \
        -Zbuild-std=core,alloc,compiler_builtins
for crate in core alloc compiler_builtins; do
    for f in "$TARGET/wasm32-unknown-unknown/release/build/$crate"/*/out/lib"$crate"-*.rlib \
             "$TARGET/wasm32-unknown-unknown/release/build/$crate"/*/out/lib"$crate"-*.rmeta; do
        [ -f "$f" ] && cp "$f" "$SYS/lib/rustlib/wasm32-unknown-unknown/lib/"
    done
done
echo "rustc.wasm-built sysroot at $SYS"
ls -lh "$SYS/lib/rustlib/wasm32-unknown-unknown/lib"
