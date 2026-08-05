#!/bin/bash
# aero-ci-repin-rerun.sh — rerun the Aero CI run that failed because the
# runner un-pinned itself to 2.336.0.
#
# Companion to runner-repin-guard.sh on the Mini: after a re-pin the guard
# leaves ~/actions-runner/.repin-rerun-pending; this script (LaunchAgent
# com.rymanov.aero.repin-rerun on the Air, every 15 min) sees the flag,
# reruns the latest run if it failed, and clears the flag. gh is
# authenticated on the Air only, which is why this half lives here.
#
# Installed at ~/bin/aero-ci-repin-rerun.sh on the Air (user Mike).
# The tracked copy at the project root is the SSOT — re-sync after edits.
#
# REMOVE the LaunchAgent and this script when a runner release >2.336.0
# ships and the pin is dropped (together with the Mini guard).

set -u

GH="$HOME/.local/bin/gh"
REPO="rymanov/Aero"
LOG="$HOME/Library/Logs/aero-ci-repin-rerun.log"
FLAG='~/actions-runner/.repin-rerun-pending'   # path on the Mini (Home)
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 mini-home"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

$SSH "test -f $FLAG" 2>/dev/null || exit 0

repinned_at=$($SSH "cat $FLAG" 2>/dev/null)
echo "$(ts) re-pin flag found (Mini re-pinned at: ${repinned_at:-unknown})" >>"$LOG"

latest=$("$GH" run list -R "$REPO" -L 1 --json databaseId,status,conclusion \
    --jq '.[0] | "\(.databaseId) \(.status) \(.conclusion)"' 2>>"$LOG")
if [ -z "$latest" ]; then
    echo "$(ts) gh run list failed — leaving flag for retry" >>"$LOG"
    exit 1
fi
read -r run_id run_status run_conclusion <<<"$latest"

if [ "$run_status" != "completed" ]; then
    echo "$(ts) latest run $run_id still $run_status — leaving flag for retry" >>"$LOG"
    exit 0
fi

if [ "$run_conclusion" = "failure" ]; then
    if "$GH" run rerun "$run_id" -R "$REPO" >>"$LOG" 2>&1; then
        echo "$(ts) reran failed run $run_id" >>"$LOG"
    else
        echo "$(ts) rerun of $run_id FAILED — leaving flag for retry" >>"$LOG"
        exit 1
    fi
else
    echo "$(ts) latest run $run_id concluded $run_conclusion — nothing to rerun" >>"$LOG"
fi

$SSH "rm -f $FLAG" && echo "$(ts) flag cleared" >>"$LOG"
