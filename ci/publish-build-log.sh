#!/usr/bin/env bash
# Publish a CI build log as an asset on the rolling `ci-logs` pre-release, so
# the full log can be read without signing in to GitHub.
#
# Usage: publish-build-log.sh <log-file> <job-name>
#
# Required environment (provided by the workflow):
#   GH_TOKEN            workflow GITHUB_TOKEN with contents: write
#   GITHUB_REPOSITORY   owner/repo
#   GITHUB_RUN_ID       current run id
#
# The asset is named <job>-<run_id>.log and replaces any previous asset for the
# same job (each run gets a new run id, so old runs stay available until the
# same job runs again). Public URL:
#   https://github.com/<owner>/<repo>/releases/download/ci-logs/<job>-<run_id>.log
set -euo pipefail

log=${1:?usage: publish-build-log.sh <log-file> <job-name>}
job=${2:?usage: publish-build-log.sh <log-file> <job-name>}

if [ ! -f "$log" ]; then
    echo "::warning::build log $log does not exist; nothing to publish"
    exit 0
fi

tag=ci-logs
asset="${job}-${GITHUB_RUN_ID}.log"
url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag}/${asset}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$log" "$tmp/$asset"

# Several jobs publish to the same release, so creating it can race: ignore a
# failed create and let the upload below decide whether the release exists.
if ! gh release view "$tag" >/dev/null 2>&1; then
    gh release create "$tag" \
        --prerelease \
        --title "CI build logs" \
        --notes "Rolling pre-release with the full build.log of rustc.wasm CI runs. Asset names are <job>-<run_id>.log; the same job replaces its asset on the next run." \
        || true
fi

gh release upload "$tag" "$tmp/$asset" --clobber

echo "::notice title=build log published::${url}"
{
    echo "### Build log"
    echo
    echo "[${asset}](${url})"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
