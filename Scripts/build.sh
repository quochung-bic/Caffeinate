#!/usr/bin/env bash
#
# build.sh — build Caffeinate.app from the command line.
#
# Why this exists rather than calling xcodebuild directly:
#
#   1. Xcode's default derived data path is a hash under
#      ~/Library/Developer/Xcode/DerivedData that differs per checkout, so
#      "where is the .app" has no fixed answer. This script pins that location
#      and copies the product somewhere predictable.
#   2. A Release build MUST be universal, and this is a silent class of failure:
#      an arm64-only build runs perfectly on the machine that produced it and
#      dies for every Intel user. That check belongs in the build, not on a list
#      someone has to remember.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT="${REPO_ROOT}/Caffeinate.xcodeproj"
readonly SCHEME="Caffeinate"
readonly DERIVED_DATA="${REPO_ROOT}/build/DerivedData"

configuration="Release"
output_dir="${REPO_ROOT}/build"
run_tests=false
build_app=true
do_clean=false
quiet=false

usage() {
    cat <<'EOF'
Usage: Scripts/build.sh [options]

Builds Caffeinate.app, and for a Release build verifies that the binary really
is universal (arm64 + x86_64).

Options:
  -d, --debug           Debug configuration, host architecture only (faster)
  -r, --release         Release configuration, universal binary (default)
  -t, --test            Run the full test suite before building
  -T, --test-only       Run the tests and stop
  -c, --clean           Delete derived data before building
  -o, --output DIR      Where to put Caffeinate.app (default: ./build)
  -q, --quiet           Show only warnings, errors and test results
  -h, --help            Print this help

Examples:
  Scripts/build.sh                     # Release build into ./build
  Scripts/build.sh --debug --clean     # a clean Debug build
  Scripts/build.sh --test-only         # 69 unit tests + 3 UI tests
EOF
}

log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)     configuration="Debug"; shift ;;
        -r|--release)   configuration="Release"; shift ;;
        -t|--test)      run_tests=true; shift ;;
        -T|--test-only) run_tests=true; build_app=false; shift ;;
        -c|--clean)     do_clean=true; shift ;;
        -o|--output)    [[ $# -ge 2 ]] || die "--output needs a directory"
                        output_dir="$2"; shift 2 ;;
        -q|--quiet)     quiet=true; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              usage >&2; die "unknown option: $1" ;;
    esac
done

# Check before starting. `xcodebuild` still exists as a stub when only the
# Command Line Tools are installed, and in that case it fails late with a
# confusing licence message — so confirm it really points at a full Xcode.
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install Xcode 16 or newer."
if ! xcodebuild -version >/dev/null 2>&1; then
    die "xcodebuild is not usable. Point it at a full Xcode install:
    sudo xcode-select -s /Applications/Xcode.app"
fi

xcb() {
    if [[ "${quiet}" == true ]]; then
        # xcbeautify and xcpretty are not project dependencies; filter by hand
        # instead, keeping only diagnostics and results. The patterns are
        # anchored deliberately: the bare word "warning" also appears inside the
        # compiler command lines xcodebuild echoes (-suppress-warnings,
        # --warnings), and without anchors every one of those 4 KB lines would
        # slip through.
        #
        # `|| true` sits INSIDE the braces so a grep that matches nothing does
        # not mask xcodebuild's exit status — `set -o pipefail` at the top of
        # the script surfaces that status out of the pipeline.
        xcodebuild "$@" | { grep -E '(^\*\*|: (error|warning): |^Test Case |^Executed |^Testing (failed|succeeded))' || true; }
        return
    fi
    xcodebuild "$@"
}

cd "${REPO_ROOT}"

if [[ "${do_clean}" == true ]]; then
    log "Deleting derived data"
    rm -rf "${DERIVED_DATA}"
    rm -rf "${REPO_ROOT}/CaffeinateKit/.build"
fi

if [[ "${run_tests}" == true ]]; then
    # The package tests are the fast, deterministic layer — run them first so a
    # broken core goes red in a second rather than after a full app build.
    log "Running the core unit tests (CaffeinateKit)"
    swift test --package-path CaffeinateKit

    log "Running the UI tests (takes over the screen for about a minute)"
    xcb -project "${PROJECT}" \
        -scheme "${SCHEME}" \
        -destination 'platform=macOS' \
        -derivedDataPath "${DERIVED_DATA}" \
        test
fi

if [[ "${build_app}" != true ]]; then
    log "Tests green"
    exit 0
fi

log "Building ${SCHEME} (${configuration})"
xcb -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${configuration}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    build

built_app="${DERIVED_DATA}/Build/Products/${configuration}/${SCHEME}.app"
[[ -d "${built_app}" ]] || die "the build reported success but ${built_app} is missing"

mkdir -p "${output_dir}"
# Delete the old bundle rather than copying over it: `cp -R` merges into an
# existing directory, so leftover resources from a previous build can survive.
rm -rf "${output_dir:?}/${SCHEME}.app"
cp -R "${built_app}" "${output_dir}/"
final_app="${output_dir}/${SCHEME}.app"

binary="${final_app}/Contents/MacOS/${SCHEME}"
architectures="$(lipo -archs "${binary}")"

if [[ "${configuration}" == "Release" ]]; then
    for arch in arm64 x86_64; do
        case " ${architectures} " in
            *" ${arch} "*) ;;
            *) die "the Release build is not universal: got '${architectures}', missing ${arch}" ;;
        esac
    done
fi

log "Built ${final_app}"
printf '    configuration : %s\n' "${configuration}"
printf '    architectures : %s\n' "${architectures}"
printf '    version       : %s (%s)\n' \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${final_app}/Contents/Info.plist" 2>/dev/null || echo '?')" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${final_app}/Contents/Info.plist" 2>/dev/null || echo '?')"

if [[ "${configuration}" == "Debug" ]]; then
    warn "A Debug build is single-architecture and unoptimized. Use --release to ship."
fi

# When install.sh calls in here it handles installation itself, and printing a
# second way to install right before it does that would only confuse the reader.
if [[ -z "${CAFFEINATE_INSTALLING:-}" ]]; then
    cat <<EOF

Install:
    ./Scripts/install.sh          # rebuild and place it in /Applications
    cp -R "${final_app}" /Applications/    # or copy it by hand

Launch at login only works while the app lives in /Applications — that is an
SMAppService requirement, not a preference.
EOF
fi
