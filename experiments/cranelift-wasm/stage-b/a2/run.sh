#!/usr/bin/env bash
# A.2 measurement driver. Reuses the Stage-A isolated rustup/cargo and patched
# cg_clif dylib; all build outputs go under toolchain/target/a2 (gitignored).
set -euo pipefail

A2=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAGE_A=$(cd "$A2/../.." && pwd)

export RUSTUP_HOME="$STAGE_A/toolchain/rustup"
export CARGO_HOME="$STAGE_A/toolchain/cargo"
export PATH="$CARGO_HOME/bin:$PATH"
export RUSTUP_TOOLCHAIN=nightly-2026-10-19
export CARGO_TARGET_DIR="$STAGE_A/toolchain/target/a2/harness"

if [ ! -x "$CARGO_TARGET_DIR/release/a2-harness" ]; then
    echo "== building A.2 harness" >&2
    cargo build --release --manifest-path "$A2/harness/Cargo.toml"
fi

echo "== measuring (e) maths node and (f) host-call geometry" >&2
exec python3 "$A2/scripts/measure_a2.py"
