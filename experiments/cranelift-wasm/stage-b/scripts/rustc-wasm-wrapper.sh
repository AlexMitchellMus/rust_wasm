#!/usr/bin/env bash
# A RUSTC wrapper for Cargo: compile wasm32-unknown-unknown crates with
# rustc.wasm under Wasmtime; compile build scripts / proc macros with the
# native stage1 compiler. Used only by the optional pure-sysroot experiment.
set -euo pipefail
HOST=${STAGE_B_HOST:?}
RUSTC_WASM=${STAGE_B_RUSTC_WASM:?}
WILD=${STAGE_B_WILD:?}
STAGE1=${STAGE_B_STAGE1:?}
CACHE=${STAGE_B_CACHE:-}
STD_SRC=${STAGE_B_STD_SRC:-}
REAL_SRC=${STAGE_B_REAL_SRC:-}

wasm=0
mapped=()
for a in "$@"; do
    case "$a" in
        wasm32-unknown-unknown|--target=wasm32-unknown-unknown) wasm=1 ;;
    esac
    # rustc's stage1 sysroot has lib/rustlib/src/rust as a symlink to the
    # checkout. WASI path_open refuses to follow it, so hand rustc.wasm the
    # real path.
    if [ -n "$STD_SRC" ] && [ -n "$REAL_SRC" ] && [[ "$a" == "$STD_SRC"* ]]; then
        a="$REAL_SRC${a#"$STD_SRC"}"
    fi
    mapped+=("$a")
done
set -- "${mapped[@]}"
if [ "$wasm" = 1 ]; then
    args=(raw --rustc "$RUSTC_WASM" --linker "$WILD")
    [ -n "$CACHE" ] && args+=(--cache-dir "$CACHE")
    args+=(-- "$@")
    args+=(-Zcodegen-backend=cranelift "-Clinker=$WILD" -Clinker-flavor=wasm-ld)
    exec "$HOST" "${args[@]}"
else
    exec "$STAGE1" "$@"
fi
