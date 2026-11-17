#!/usr/bin/env bash
# Run a build command, tee its output to a log, and on failure surface the
# interesting parts as GitHub Actions error annotations (readable without
# access to the job logs). The log itself is uploaded by a later workflow step.
#
# Usage: build-with-diagnostics.sh <log-file> <command> [args...]
#
# Escape rules for workflow commands:
#   https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
set -uo pipefail

log=${1:?usage: build-with-diagnostics.sh <log-file> <command> [args...]}
shift

# `tee` truncates the log, so each invocation starts from a clean file.
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if [ "$status" -eq 0 ]; then
    exit 0
fi

# Escape a value for use in a workflow command message/property.
escape() {
    local s=$1
    s=${s//%/%25}
    s=${s//$'\r'/%0D}
    s=${s//$'\n'/%0A}
    printf '%s' "$s"
}

# Attributes that usually point at the real failure, even when the build
# itself only prints "exited with status 1" at the end.
pattern='error\[|error:|fatal error|undefined symbol|CMake Error|thread .* panicked|failed to run'

emit_error() {
    local title body
    title=$(escape "$1")
    body=$(escape "$2")
    # GitHub truncates annotations; keep well below the 64 KiB command limit.
    printf '::error title=%s::%s\n' "$title" "${body:0:60000}"
}

emit_error "build failed in $(basename "$log")" \
    "command failed with exit status $status: $*"

# One annotation per match, with a few lines of context. Skip text that was
# already covered by a previous match so overlapping hits are not duplicated.
last_end=0
while IFS= read -r n; do
    [ -z "$n" ] && continue
    start=$((n > 2 ? n - 2 : 1))
    end=$((n + 3))
    if [ "$start" -le "$last_end" ]; then
        start=$((last_end + 1))
    fi
    [ "$start" -gt "$end" ] && continue

    snippet=$(sed -n "${start},${end}p" "$log")
    emit_error "build error in $(basename "$log") line $n" "$snippet"
    last_end=$end
done < <(grep -n -E -m 15 -- "$pattern" "$log" | cut -d: -f1)

# Always finish with the tail of the log: it usually names the failing target
# or subcommand even when no keyword above matched.
emit_error "build failed - last 60 lines of $(basename "$log")" \
    "$(tail -n 60 "$log" | cut -c1-1000)"

exit "$status"
