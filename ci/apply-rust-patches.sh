#!/usr/bin/env bash
# Apply the rustc.wasm compiler patch series to a rust-lang/rust checkout and
# only then initialize the submodules.
#
# Usage: ci/apply-rust-patches.sh <rust-checkout> <patch-dir>
#
# The ordering is intentional: patch 0002 rewrites .gitmodules and the
# src/llvm-project gitlink to YoWASP/llvm-project llvmorg-22.1.0+wasm, so the
# submodules must be fetched after the series is applied, not before.
set -euo pipefail

rust_dir=${1:?usage: apply-rust-patches.sh <rust-checkout> <patch-dir>}
patch_dir=${2:?usage: apply-rust-patches.sh <rust-checkout> <patch-dir>}

cd "$rust_dir"

if [ ! -d "$patch_dir" ]; then
  echo "ERROR: patch directory not found: $patch_dir" >&2
  exit 1
fi

patches=$(find "$patch_dir" -maxdepth 1 -type f -name '*.patch' | sort)
if [ -z "$patches" ]; then
  echo "ERROR: no *.patch files in $patch_dir" >&2
  exit 1
fi

count=$(printf '%s\n' "$patches" | wc -l | tr -d ' ')
if [ "$count" -ne 5 ]; then
  echo "ERROR: expected exactly 5 patches in $patch_dir, found $count" >&2
  printf '%s\n' "$patches" >&2
  exit 1
fi

base=$(git rev-parse HEAD)
echo "Applying $count compiler patches on top of $base ($(git log -1 --format=%s))"
printf '%s\n' "$patches"

# Throwaway committer identity; the author is preserved from each patch.
# shellcheck disable=SC2086
GIT_COMMITTER_NAME=rust-wasm-ci \
GIT_COMMITTER_EMAIL=rust-wasm-ci@users.noreply.github.com \
  git am $patches

applied=$(git rev-list --count "$base..HEAD")
if [ "$applied" -ne "$count" ]; then
  echo "ERROR: expected $count commits after git am, found $applied" >&2
  exit 1
fi

echo "Patch series applied; HEAD is $(git rev-parse --short HEAD) ($(git log -1 --format=%s))"

# Match what actions/checkout's `submodules: true` used to do for the compiler
# fork: shallowly fetch every submodule at the gitlink recorded in the tree.
echo "Initializing submodules at the patched gitlinks (shallow)..."
git submodule sync --recursive
git submodule update --init --recursive --depth 1

echo "src/llvm-project: $(git submodule status src/llvm-project)"
echo "Submodules ready."
