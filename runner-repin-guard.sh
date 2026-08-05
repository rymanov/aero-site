#!/bin/bash
# runner-repin-guard.sh — keep the GitHub Actions runner pinned to 2.335.1.
#
# The runner force-updates itself past `"disableUpdate": true` (the 2.336.0
# post-job wedge; see aero-wiki synthesis/app-ci-on-the-mini.md). This guard
# runs from Home's cron on the Mini every 5 minutes; when the bin/externals
# symlinks drift off the pin it applies the runbook — svc stop, re-point,
# svc start — logs the event, and leaves a flag file the Air picks up to
# rerun the failed run (aero-ci-repin-rerun.sh).
#
# Installed at /Users/Media/bin/runner-repin-guard.sh on the Mini (user Home).
# The tracked copy at the project root is the SSOT — re-sync after edits.
#
# REMOVE the cron entry and this script when a runner release >2.336.0 ships
# and the pin is dropped.

set -u

PIN="2.335.1"
RUNNER_DIR="$HOME/actions-runner"
LOG="$HOME/Library/Logs/runner-repin-guard.log"
FLAG="$RUNNER_DIR/.repin-rerun-pending"
LOCK="$RUNNER_DIR/.repin-guard.lock"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

bin_now=$(basename "$(readlink "$RUNNER_DIR/bin")")
ext_now=$(basename "$(readlink "$RUNNER_DIR/externals")")
[ "$bin_now" = "bin.$PIN" ] && [ "$ext_now" = "externals.$PIN" ] && exit 0

# One re-pin at a time; a stale lock from a crashed run is cleared by age.
if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
        rmdir "$LOCK" 2>/dev/null
        mkdir "$LOCK" 2>/dev/null || exit 0
    else
        exit 0
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ ! -d "$RUNNER_DIR/bin.$PIN" ] || [ ! -d "$RUNNER_DIR/externals.$PIN" ]; then
    echo "$(ts) drift to bin=$bin_now but $PIN dirs missing — cannot re-pin" >>"$LOG"
    exit 1
fi

echo "$(ts) drift detected: bin=$bin_now externals=$ext_now — re-pinning to $PIN" >>"$LOG"
cd "$RUNNER_DIR" || exit 1
./svc.sh stop >>"$LOG" 2>&1
ln -shf "bin.$PIN" bin
ln -shf "externals.$PIN" externals
./svc.sh start >>"$LOG" 2>&1
sleep 5

bin_after=$(basename "$(readlink "$RUNNER_DIR/bin")")
if [ "$bin_after" = "bin.$PIN" ] && pgrep -f "Runner.Listener run" >/dev/null; then
    echo "$(ts) re-pinned to $PIN, listener running" >>"$LOG"
    date "+%Y-%m-%d %H:%M:%S" >"$FLAG"
else
    echo "$(ts) RE-PIN FAILED: bin=$bin_after, listener $(pgrep -f 'Runner.Listener run' >/dev/null && echo up || echo DOWN)" >>"$LOG"
    exit 1
fi
