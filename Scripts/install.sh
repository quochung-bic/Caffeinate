#!/usr/bin/env bash
#
# install.sh — build Caffeinate.app and place it in /Applications.
#
# Why this is separate from build.sh: build.sh stops at `build/Caffeinate.app`
# and prints a `cp -R … /Applications/` line for the user to run. That line is
# correct but misses three things that only surface from the second copy
# onwards — the running copy still holds the bundle about to be replaced,
# `cp -R` merges into the old directory instead of replacing it, and the app is
# an LSUIElement so nothing appears afterwards to say it worked.
#
# For someone who has just cloned the repo, this is the whole installation:
#
#   git clone https://github.com/quochung-bic/Caffeinate.git
#   cd Caffeinate
#   ./Scripts/install.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_NAME="Caffeinate"
readonly BUNDLE_ID="io.github.quochung-bic.Caffeinate"

destination="/Applications"
run_tests=false
quiet=false
build_app=true

usage() {
    cat <<'EOF'
Usage: Scripts/install.sh [options]

Builds a Release (universal) binary and installs Caffeinate.app into
/Applications.

Options:
  -d, --destination DIR   Install somewhere else (default: /Applications)
  -t, --test              Run the full test suite before building
  -n, --no-build          Install the existing build/Caffeinate.app as-is
  -q, --quiet             Show only warnings, errors and test results
  -h, --help              Print this help

Launch at login only works while the app lives in /Applications, so
--destination is for experimenting rather than an equal alternative.
EOF
}

log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--destination) [[ $# -ge 2 ]] || die "--destination needs a directory"
                          destination="$2"; shift 2 ;;
        -t|--test)        run_tests=true; shift ;;
        -n|--no-build)    build_app=false; shift ;;
        -q|--quiet)       quiet=true; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                usage >&2; die "unknown option: $1" ;;
    esac
done

readonly installed_app="${destination%/}/${APP_NAME}.app"
readonly built_app="${REPO_ROOT}/build/${APP_NAME}.app"

if [[ "${build_app}" == true ]]; then
    # build.sh suppresses its own "Install:" section when it knows it was called
    # from here.
    export CAFFEINATE_INSTALLING=1
    build_args=(--release)
    [[ "${run_tests}" == true ]] && build_args+=(--test)
    [[ "${quiet}" == true ]] && build_args+=(--quiet)
    "${REPO_ROOT}/Scripts/build.sh" "${build_args[@]}"
elif [[ "${run_tests}" == true ]]; then
    die "--no-build and --test are mutually exclusive"
fi

[[ -d "${built_app}" ]] || die "${built_app} not found. Drop --no-build to build it."

# The running copy is holding the very bundle about to be replaced. Ask it to
# quit rather than killing it: the app still has settings to write, and a live
# assertion should be released properly instead of left for the system to clean
# up.
if pgrep -f "${installed_app}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
    log "Quitting the running copy"
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -f "${installed_app}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 || break
        sleep 0.25
    done
    pgrep -f "${installed_app}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 \
        && die "the running copy will not quit. Quit it from the menu bar and try again."
fi

[[ -d "${destination}" ]] || die "${destination} does not exist"
if [[ ! -w "${destination}" ]]; then
    die "${destination} is not writable as $(whoami).
    Re-run with sudo, or install just for yourself:
    ${0} --destination \"\$HOME/Applications\""
fi

# Replace rather than copy over, for the same reason as in build.sh: `cp -R`
# merges into the existing directory, so resources from the old version that the
# new one no longer uses would stay behind inside the bundle.
log "Installing to ${installed_app}"
rm -rf "${installed_app}"
cp -R "${built_app}" "${installed_app}"

log "Opening the app"
open "${installed_app}"

if [[ "${destination%/}" != "/Applications" ]]; then
    warn "Installed outside /Applications: SMAppService will refuse to register,
         so the launch-at-login option will report an error explaining why."
fi

cat <<EOF

Caffeinate is a pure menu bar app: no Dock icon and no main window. Once it
opens, look for the **coffee cup in the menu bar** — click it for the control
panel, and press ⌘, for the Settings window.

You compiled this build yourself, so it carries no quarantine flag: Gatekeeper
neither blocks it nor asks about it. The signature is ad-hoc
(CODE_SIGN_IDENTITY = - in Configs/App.xcconfig), which is enough to run on this
Mac; distributing it to other people needs a Developer ID and notarization.

To uninstall: quit the app from the menu bar and drag the bundle to the Trash:
    ${installed_app}
The only thing it leaves behind is its own settings, at
~/Library/Preferences/${BUNDLE_ID}.plist
EOF
