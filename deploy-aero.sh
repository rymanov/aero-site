#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# deploy-aero.sh — build on the Mini, install to /Applications, relaunch on TV
#
# Every stage ends in an assertion against the artifact, not against a claim about
# it. The four checks, and the bug each one exists to kill:
#
#   1. Force-recompile this target  -> the stale-.o trap (builds 73-77). xcodebuild
#                                      prints SUCCEEDED, reuses an old object, and the
#                                      app you install does not contain your change.
#   2. Surface error: lines         -> a real failure scrolling past in the firehose.
#   3. Gate install on .o vs .swift -> installing a product that did not recompile.
#   4. Assert the RUNNING version   -> "quit" silently failing, so open(1) merely
#                                      activates the OLD process and you spend an
#                                      evening debugging a binary that is not on disk.
#
# Structural change from the previous version: the remote payloads are quoted
# heredocs (<<'REMOTE') instead of single-quoted ssh strings. They go over verbatim
# with no local expansion, and an apostrophe in a comment can no longer break the
# script. It did once, during the Xtream campaign.
# ---------------------------------------------------------------------------

echo "=== Building on Mini ==="
ssh mini-admin bash -s <<'REMOTE'
set -euo pipefail
cd ~/dev/aero
git pull

# Clear THIS target's intermediates plus the build database. That is what defeats the
# stale-object trap. VLCKit is a prebuilt xcframework under Vendor/VLCKitLGPL and is
# not compiled here, so its products are untouched: this costs a Swift recompile, not
# a VLCKit rebuild.
rm -rf build/Build/Intermediates.noindex/Aero.build build/XCBuildData

# CODE_SIGN_ENTITLEMENTS= drops the project's Aero.entitlements (keychain-access-groups)
# for this self-signed build: that entitlement requires a provisioning profile under
# manual signing, and amfi would SIGKILL the app for claiming it unsigned-by-a-team
# anyway. App Sandbox + network stay (they come from build settings). The app then
# uses its encrypted-file secret fallback; the Developer-ID archive KEEPS the
# entitlement and uses the (SEP-backed) data-protection keychain: zero prompts.
#
# Output goes to a log, so this stage is silent. It is also a FULL recompile of the
# app target, not the incremental build this script used to do, so it takes minutes.
echo "  compiling (full recompile, a few minutes; output -> /tmp/aero-build.log on the Mini)"
set +e
xcodebuild -scheme Aero -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= build > /tmp/aero-build.log 2>&1
STATUS=$?
set -e
if [ $STATUS -ne 0 ]; then
  echo "  BUILD FAILED:"
  grep -E "error:" /tmp/aero-build.log | head -40
  echo "  (full log on the Mini: /tmp/aero-build.log)"
  exit 1
fi
# xcodebuild can exit 0 with error: lines in some configurations. Say so.
if grep -qE "error:" /tmp/aero-build.log; then
  echo "  WARNING: error: lines in a build that exited 0:"
  grep -E "error:" /tmp/aero-build.log | head -20
fi
echo "  -> build OK"

# Install gate. After a forced recompile, every object must be newer than every
# source. If any .swift is newer than the OLDEST .o, the recompile did not take.
OLDEST_O=$(find build/Build/Intermediates.noindex/Aero.build -name '*.o' -exec stat -f '%m %N' {} + 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
if [ -z "$OLDEST_O" ]; then
  echo "  ERROR: no .o files under build/Build/Intermediates.noindex/Aero.build"
  echo "  The intermediates path has changed. Fix this check, do not delete it."
  exit 1
fi
STALE=$(find . -name '*.swift' -not -path './build/*' -not -path './Vendor/*' -newer "$OLDEST_O" | head -5)
if [ -n "$STALE" ]; then
  echo "  ERROR: sources newer than compiled objects. Stale build, refusing to install:"
  echo "$STALE"
  exit 1
fi
echo "  -> every object is newer than every source"
REMOTE

# The app enables Hardened Runtime, which turns on Library Validation. That rejects
# the embedded (differently-signed) VLCKit.framework at load time with a "different
# Team IDs" dyld error, so the app dies instantly on launch. Re-sign with the
# auto-generated entitlements PLUS disable-library-validation.
#
# Sign with the STABLE self-signed "Aero Local Signing" identity when it is set up (see
# the one-time-setup note at the bottom of this file). Its designated requirement is
# cert-based — "identifier … and certificate leaf = H\"…\"" — so it is IDENTICAL across
# every build. That lets the TV's "Always Allow" keychain grants survive a redeploy.
# Ad-hoc's requirement is the per-build cdhash, which changes every time, so ad-hoc
# re-prompts for each stored secret (playlist token, caches, trial) on every deploy.
# Falls back to ad-hoc automatically if the identity is absent, so this is safe.
echo "=== Re-signing (allow embedded VLCKit) ==="
ssh mini-admin bash -s <<'REMOTE'
set -euo pipefail
cd ~/dev/aero
APP=build/Build/Products/Release/Aero.app

codesign -d --entitlements - --xml "$APP" 2>/dev/null > /tmp/aero-ent.plist
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.cs.disable-library-validation" /tmp/aero-ent.plist 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" /tmp/aero-ent.plist

# Strip keychain-access-groups for the self-signed re-sign: amfi SIGKILLs a
# non-team-signed binary that claims it. Without it, the app cannot use the
# data-protection keychain and falls back to its own encrypted-file secret
# store (see KeychainStore.swift). The Developer-ID archive KEEPS the
# entitlement and uses the (SEP-backed) data-protection keychain: zero prompts.
/usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" /tmp/aero-ent.plist 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" /tmp/aero-ent.plist 2>/dev/null || true

# NOTE: keychain-access-groups was tried here to move secrets to the data-protection keychain (no ACL
# prompt) — but amfi rejects a self-asserted keychain-access-groups on a self-signed app → launch
# failure. Removed. The keychain-prompt fix is instead to TRUST the "Aero Local Signing" cert once
# from a GUI session (macOS blocks trust changes over ssh): on the Mini console/VNC run
#   security add-trusted-cert -r trustRoot -p codeSign /Users/Shared/aero-signing-cert.pem
KC="$HOME/Library/Keychains/aero-signing.keychain-db"
if [ -f "$HOME/.aero-signing-pw" ] && security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "Aero Local Signing"; then
  security unlock-keychain -p "$(cat "$HOME/.aero-signing-pw")" "$KC"
  echo "  -> stable identity: Aero Local Signing"
  codesign --force --sign "Aero Local Signing" --keychain "$KC" --options runtime --entitlements /tmp/aero-ent.plist "$APP"
else
  echo "  -> ad-hoc (stable identity not found; TV keychain prompts will recur)"
  codesign --force --sign - --options runtime --entitlements /tmp/aero-ent.plist "$APP"
fi
REMOTE

# Read the identity of what we just built, straight off the artifact.
#
# Deliberately NOT cross-checked against CURRENT_PROJECT_VERSION in project.pbxproj.
# The first version of this script did that and it was incoherent: CFBundleVersion is
# GENERATED from CURRENT_PROJECT_VERSION at build time, so for the Aero target the two
# cannot disagree. A mismatch only ever means the grep found a different target (it
# found one sitting at 1, and warned on every deploy). The check could produce false
# alarms and nothing else, so it is gone rather than fixed.
INFO=$(ssh mini-admin bash -s <<'REMOTE'
set -euo pipefail
cd ~/dev/aero
V=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" build/Build/Products/Release/Aero.app/Contents/Info.plist)
S=$(git rev-parse --short HEAD)
echo "$V|$S"
REMOTE
)
BUILT="${INFO%%|*}"
SHA="${INFO#*|}"

echo "=== Installing (build $BUILT @ $SHA) ==="
ssh mini-admin bash -s <<'REMOTE'
set -euo pipefail
rm -rf /Applications/Aero.app
cp -R ~/dev/aero/build/Build/Products/Release/Aero.app /Applications/
REMOTE

INSTALLED=$(ssh mini-admin '/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Applications/Aero.app/Contents/Info.plist')
if [ "$INSTALLED" != "$BUILT" ]; then
  echo "ERROR: /Applications holds build $INSTALLED, we built $BUILT. The copy did not land."
  exit 1
fi
echo "  -> /Applications/Aero.app is build $INSTALLED"

# Relaunch. open(1) returns 0 the instant it hands off to LaunchServices, so it cannot
# tell us the app stayed up. Worse: if the quit silently fails, open just ACTIVATES the
# running old process and reports success. So: quit, wait for the process to actually
# die, force it if it will not, and only then launch.
echo "=== Relaunching on TV ==="
ssh mini-home bash -s <<'REMOTE'
set -uo pipefail
BIN=/Applications/Aero.app/Contents/MacOS/Aero

osascript -e 'quit app "Aero"' 2>/dev/null || true
for _ in $(seq 1 15); do
  pgrep -f "$BIN" >/dev/null || break
  sleep 1
done
if pgrep -f "$BIN" >/dev/null; then
  echo "  -> did not quit in 15s, forcing"
  pkill -9 -f "$BIN" || true
  sleep 2
fi
if pgrep -f "$BIN" >/dev/null; then
  echo "ERROR: could not stop the old Aero. Refusing to claim a fresh launch."
  exit 1
fi

open /Applications/Aero.app
sleep 4
if ! pgrep -f "$BIN" >/dev/null; then
  echo "ERROR: Aero failed to stay running after launch"
  exit 1
fi
echo "  -> launched and still up after 4s"
REMOTE

# The old process was proven dead before open(1) ran, so what is running now was
# loaded from the bundle we just verified on disk.
RUNNING=$(ssh mini-home '/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Applications/Aero.app/Contents/Info.plist')
if [ "$RUNNING" != "$BUILT" ]; then
  echo "ERROR: TV is running build $RUNNING, we built $BUILT."
  exit 1
fi

echo "=== Done: TV runs build $BUILT @ $SHA ==="

# ---------------------------------------------------------------------------
# ONE-TIME SETUP that stops the repeated TV keychain password prompts on deploy
# ---------------------------------------------------------------------------
# The re-sign step above uses a stable self-signed identity ("Aero Local Signing")
# living in ~/Library/Keychains/aero-signing.keychain-db on mini-admin, with its
# password in ~/.aero-signing-pw (chmod 600). It was created by:
#
#   scp ~/bin/setup-aero-signing.sh mini-admin:/tmp/ && ssh mini-admin 'bash /tmp/aero-setup-signing.sh'
#
# To (re)create it — e.g. if the Mini is rebuilt — run that again (idempotent).
#
# On the FIRST deploy after switching from ad-hoc to this identity, the app's code
# signature changes once, so the TV (mini-home) will show the "Aero wants to use your
# confidential information" dialog ~6 times — click **Always Allow** each time. Because
# the identity's designated requirement is now cert-based (stable across every future
# build), those grants stick and the prompts do NOT come back on later deploys.
# ---------------------------------------------------------------------------
