#!/usr/bin/env bash
# Anti-pattern review scan for rust_wasm's own code (agents/skills/anti-pattern-review.md).
#
#   agents/scripts/review-scan.sh            scan everything we own
#   agents/scripts/review-scan.sh --changed  only crates/files changed against origin/main
#   agents/scripts/review-scan.sh --strict   also fail on fmt/clippy/shellcheck/ruff findings
#
# ast-grep error-level rules always fail the scan. Other tools report findings
# and fail only with --strict, until existing findings are fixed (see
# agents/ROADMAP.md, Quality work). A tool that isn't installed is skipped with
# a message, never silently.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

changed=0
strict=0
for arg in "$@"; do
  case "$arg" in
    --changed) changed=1 ;;
    --strict) strict=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

failed=0      # findings that always fail
soft=0        # findings that fail only with --strict
note() { printf '\n== %s\n' "$*"; }
# Read lines from stdin into the named array (bash 3.2 has no mapfile).
read_into() { local _name="$1" _line; eval "$_name=()"; while IFS= read -r _line; do
  [[ -n "$_line" ]] && eval "$_name+=(\"\$_line\")"; done; }
skip() { printf '   skipped: %s\n' "$*"; }

# Our own code: everything tracked except patches for upstream projects, upstream
# drafts, the legacy LLVM series and the rule fixtures.
own_files() {
  git ls-files -- "$@" \
    | grep -v -E '^(patches/|.*/upstream/|.*/toolchain/|agents/scripts/rule-fixtures/)' || true
}
if [[ $changed -eq 1 ]]; then
  base="$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD)"
  changed_list="$(git diff --name-only "$base" -- . ; git ls-files --others --exclude-standard)"
  in_scope() { grep -F -x -f <(printf '%s\n' "$changed_list") || true; }
else
  in_scope() { cat; }
fi

# 1. The project rules still match their known examples.
note "ast-grep rule self-test"
if command -v ast-grep >/dev/null; then
  expected="allow-needs-expect no-dbg-macro no-ignored-tests no-process-exit-in-library no-sleep-to-fix-ordering no-todo-in-code"
  found="$(ast-grep scan --json=compact agents/scripts/rule-fixtures/bad.rs 2>/dev/null \
    | python3 -I -c 'import json,sys; print(" ".join(sorted({x["ruleId"] for x in json.load(sys.stdin)})))' || true)"
  if [[ "$found" != "$expected" ]]; then
    echo "   rules no longer match their fixtures: expected [$expected], got [$found]"; failed=1
  else
    echo "   all rules match bad.rs"
  fi
else
  skip "ast-grep not installed"
fi

# 2. Project anti-pattern rules.
note "ast-grep scan"
if command -v ast-grep >/dev/null; then
  read_into rs_files < <(own_files '*.rs' | in_scope)
  if [[ ${#rs_files[@]:-0} -gt 0 ]]; then
    if ! ast-grep scan "${rs_files[@]}"; then failed=1; fi
  else
    echo "   no Rust files in scope"
  fi
else
  skip "ast-grep not installed"
fi

# 3. Host-side Rust crates: formatting and clippy. Guest crates built for wasm
# (no_std, custom panic handlers) are checked by the build itself.
note "cargo fmt / clippy (host crates)"
host_crates=()
for m in $(own_files '*Cargo.toml' | sort -u); do
  if grep -q -E '^\s*wasmtime\s*=|^\s*clap\s*=' "$m" || [[ "$m" == config_rewriter/Cargo.toml ]]; then
    dir="$(dirname "$m")"
    if [[ $changed -eq 1 ]] && ! printf '%s\n' "$changed_list" | grep -q "^$dir/"; then continue; fi
    host_crates+=("$m")
  fi
done
if [[ ${#host_crates[@]} -eq 0 ]]; then
  echo "   no host crates in scope"
elif ! cargo clippy --version >/dev/null 2>&1; then
  skip "cargo clippy not installed (rustup component add clippy rustfmt)"
else
  export CLIPPY_CONF_DIR="$root"
  for m in "${host_crates[@]}"; do
    echo "   $m"
    if ! cargo fmt --manifest-path "$m" --check >/dev/null 2>&1; then
      echo "     fmt: needs formatting (cargo fmt --manifest-path $m)"; soft=1
    fi
    if ! cargo clippy --quiet --manifest-path "$m" --all-targets -- \
        -W clippy::all -W clippy::pedantic \
        -W clippy::excessive_nesting -W clippy::unwrap_used -W clippy::dbg_macro -W clippy::todo \
        -W clippy::undocumented_unsafe_blocks -W unsafe_op_in_unsafe_fn \
        -A clippy::module_name_repetitions -A clippy::must_use_candidate \
        -A clippy::missing_errors_doc -A clippy::missing_panics_doc \
        -D warnings 2>&1 | tail -n 40; then
      soft=1
    fi
  done
fi

# 4. Shell scripts.
note "shellcheck"
read_into sh_files < <(own_files '*.sh' | in_scope)
if [[ ${#sh_files[@]} -eq 0 ]]; then
  echo "   no shell scripts in scope"
elif command -v shellcheck >/dev/null; then
  shellcheck -S warning "${sh_files[@]}" || soft=1
else
  skip "shellcheck not installed"
fi

# 5. Python scripts.
note "ruff"
read_into py_files < <(own_files '*.py' | in_scope)
if [[ ${#py_files[@]} -eq 0 ]]; then
  echo "   no Python files in scope"
elif command -v ruff >/dev/null; then
  ruff check "${py_files[@]}" || soft=1
else
  skip "ruff not installed"
fi

note "summary"
if [[ $failed -ne 0 ]]; then
  echo "   FAIL: error-level findings (see above)"; exit 1
fi
if [[ $soft -ne 0 ]]; then
  if [[ $strict -eq 1 ]]; then echo "   FAIL (--strict): findings above"; exit 1; fi
  echo "   findings reported above (not blocking yet; use --strict to enforce)"
  exit 0
fi
echo "   clean"
