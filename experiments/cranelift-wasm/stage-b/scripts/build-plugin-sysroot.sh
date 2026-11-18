#!/usr/bin/env bash
# Build a wasm32-unknown-unknown sysroot for plugin (c).
#
# Two modes:
#   pure   (default) Stage A's patched cg_clif compiles core/alloc/
#          compiler_builtins => pure-Rust rlibs. Fast, but the rlibs are built
#          by rustup's nightly (`1.101.0-nightly`), while rustc.wasm reports
#          `1.101.0-dev`; rustc rejects them with E0514. Kept for comparison.
#   stage1 build the same crates with the native stage1 compiler produced by
#          the rustc.wasm build. Its version string is exactly rustc.wasm's,
#          so rustc.wasm accepts the sysroot. This is LLVM-built code (the one
#          build-time LLVM use), but it is *outside* rustc.wasm.
#
# Usage: build-plugin-sysroot.sh [pure|stage1]
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)   # experiments/cranelift-wasm
TOOL="$ROOT/toolchain"
MODE="${1:-pure}"
TRIPLE=wasm32-unknown-unknown

export RUSTUP_HOME="${RUSTUP_HOME:-$TOOL/rustup}"
export CARGO_HOME="${CARGO_HOME:-$TOOL/cargo}"
export RUSTUP_TOOLCHAIN=nightly-2026-10-19
# compiler_builtins' build script invokes rust-objcopy from the rustup tools.
export PATH="$CARGO_HOME/bin:$RUSTUP_HOME/toolchains/nightly-2026-10-19-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/bin:$PATH"

DYLIB="$TOOL/target/cg_clif/release/librustc_codegen_cranelift.dylib"
SRC="$ROOT/programs/c_plugin"

case "$MODE" in
    pure)
        TARGET="$TOOL/target/stage-b-sysroot"
        SYS="$TOOL/stage-b/sysroot-pure"
        [ -f "$DYLIB" ] || { echo "missing patched cg_clif: $DYLIB" >&2; exit 1; }
        rm -rf "$TARGET" "$SYS"
        mkdir -p "$SYS/lib/rustlib/$TRIPLE/lib"
        ( cd "$SRC" && RUSTFLAGS="-Zcodegen-backend=$DYLIB -Cpanic=abort" \
            CARGO_TARGET_DIR="$TARGET" \
            cargo build --release --target "$TRIPLE" \
                -Zbuild-std=core,alloc,compiler_builtins )
        ;;
    stage1)
        STAGE1="$TOOL/stage-b/rust/build/host/stage1/bin/rustc"
        [ -x "$STAGE1" ] || { echo "missing stage1 rustc: $STAGE1" >&2; exit 1; }
        TARGET="$TOOL/target/stage-b-sysroot-stage1"
        SYS="$TOOL/stage-b/sysroot-stage1"
        rm -rf "$TARGET" "$SYS"
        mkdir -p "$SYS/lib/rustlib/$TRIPLE/lib"
        ( cd "$SRC" && RUSTC="$STAGE1" RUSTC_BOOTSTRAP=1 \
            CARGO_TARGET_DIR="$TARGET" \
            cargo build --release --target "$TRIPLE" \
                -Zbuild-std=core,alloc,compiler_builtins )
        ;;
    *)
        echo "usage: $0 [pure|stage1]" >&2; exit 1 ;;
esac

for crate in core alloc compiler_builtins; do
    found=0
    for f in "$TARGET/$TRIPLE/release/build/$crate"/*/out/lib"$crate"-*.rlib \
             "$TARGET/$TRIPLE/release/build/$crate"/*/out/lib"$crate"-*.rmeta; do
        [ -f "$f" ] || continue
        cp "$f" "$SYS/lib/rustlib/$TRIPLE/lib/"
        found=1
    done
    [ "$found" = 1 ] || { echo "no $crate rlib under $TARGET" >&2; exit 1; }
done

echo "$MODE sysroot at $SYS:"
ls -lh "$SYS/lib/rustlib/$TRIPLE/lib"
