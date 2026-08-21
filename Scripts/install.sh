#!/usr/bin/env bash
#
# install.sh — dựng Caffeinate.app rồi đặt vào /Applications.
#
# Vì sao tách khỏi build.sh: build.sh dừng ở `build/Caffeinate.app` và in ra
# dòng `cp -R … /Applications/` để người dùng tự chép. Dòng ấy đúng nhưng thiếu
# ba việc mà lần chép thứ hai trở đi mới lộ ra — bản cũ đang chạy vẫn giữ bundle
# sắp bị thay, `cp -R` trộn vào thư mục cũ thay vì thay hẳn nó, và app là
# LSUIElement nên chép xong không có gì hiện ra để biết là đã xong.
#
# Với người vừa clone repo về, đây là toàn bộ phần cài đặt:
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
Cách dùng: Scripts/install.sh [tuỳ chọn]

Dựng bản Release (universal binary) rồi cài Caffeinate.app vào /Applications.

Tuỳ chọn:
  -d, --destination DIR   Cài vào chỗ khác (mặc định: /Applications)
  -t, --test              Chạy toàn bộ test trước khi dựng
  -n, --no-build          Cài thẳng build/Caffeinate.app đang có sẵn
  -q, --quiet             Chỉ hiện cảnh báo, lỗi và kết quả test
  -h, --help              In trợ giúp này

Khởi động cùng macOS chỉ hoạt động khi app nằm trong /Applications, nên
--destination là để thử nghiệm chứ không phải một lựa chọn ngang hàng.
EOF
}

log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mcảnh báo:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mlỗi:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--destination) [[ $# -ge 2 ]] || die "--destination cần một thư mục"
                          destination="$2"; shift 2 ;;
        -t|--test)        run_tests=true; shift ;;
        -n|--no-build)    build_app=false; shift ;;
        -q|--quiet)       quiet=true; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                usage >&2; die "tuỳ chọn không hiểu: $1" ;;
    esac
done

readonly installed_app="${destination%/}/${APP_NAME}.app"
readonly built_app="${REPO_ROOT}/build/${APP_NAME}.app"

if [[ "${build_app}" == true ]]; then
    # build.sh im phần "Cài đặt:" của nó khi biết đang bị gọi từ đây.
    export CAFFEINATE_INSTALLING=1
    build_args=(--release)
    [[ "${run_tests}" == true ]] && build_args+=(--test)
    [[ "${quiet}" == true ]] && build_args+=(--quiet)
    "${REPO_ROOT}/Scripts/build.sh" "${build_args[@]}"
elif [[ "${run_tests}" == true ]]; then
    die "--no-build và --test loại trừ nhau"
fi

[[ -d "${built_app}" ]] || die "không thấy ${built_app}. Bỏ --no-build để dựng nó."

# Bản đang chạy đang giữ chính cái bundle sắp bị thay. Bảo nó thoát chứ không
# giết: app còn phải ghi lại cài đặt, và một assertion còn treo phải được nhả ra
# tử tế thay vì để hệ thống dọn hộ.
if pgrep -f "${installed_app}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
    log "Thoát bản đang chạy"
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -f "${installed_app}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 || break
        sleep 0.25
    done
    pgrep -f "${installed_app}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 \
        && die "bản đang chạy không chịu thoát. Thoát nó từ thanh menu rồi chạy lại."
fi

[[ -d "${destination}" ]] || die "${destination} không tồn tại"
if [[ ! -w "${destination}" ]]; then
    die "${destination} không ghi được bằng tài khoản $(whoami).
    Chạy lại bằng sudo, hoặc cài riêng cho mình:
    ${0} --destination \"\$HOME/Applications\""
fi

# Thay hẳn chứ không chép đè, cùng lý do như trong build.sh: `cp -R` trộn vào
# thư mục đang có, nên tài nguyên của bản cũ mà bản mới không còn dùng vẫn nằm
# lại trong bundle.
log "Cài vào ${installed_app}"
rm -rf "${installed_app}"
cp -R "${built_app}" "${installed_app}"

log "Mở app"
open "${installed_app}"

if [[ "${destination%/}" != "/Applications" ]]; then
    warn "Cài ngoài /Applications: SMAppService sẽ từ chối đăng ký, nên tuỳ chọn
         khởi động cùng macOS sẽ báo lỗi và nói rõ vì sao."
fi

cat <<EOF

Caffeinate là app thanh menu thuần: không có icon Dock và không có cửa sổ chính.
Mở xong thì tìm **biểu tượng ly cà phê trên thanh menu**, bấm vào đó là ra bảng
điều khiển; ⌘, mở cửa sổ Cài đặt.

Bản này bạn tự biên dịch nên không mang cờ quarantine — Gatekeeper không chặn và
cũng không hỏi gì. Chữ ký là ad-hoc (CODE_SIGN_IDENTITY = - trong
Configs/App.xcconfig), đủ để chạy trên máy này; muốn phát hành cho người khác
tải về thì cần Developer ID và notarize.

Gỡ cài đặt: thoát app từ thanh menu rồi kéo bundle vào Thùng rác:
    ${installed_app}
Thứ duy nhất nó để lại là cài đặt của chính nó, ở
~/Library/Preferences/${BUNDLE_ID}.plist
EOF
