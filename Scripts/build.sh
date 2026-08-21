#!/usr/bin/env bash
#
# build.sh — dựng Caffeinate.app từ dòng lệnh.
#
# Vì sao cần script này thay vì gọi thẳng xcodebuild:
#
#   1. Đường dẫn derived data mặc định của Xcode là một chuỗi băm nằm dưới
#      ~/Library/Developer/Xcode/DerivedData, khác nhau ở từng bản checkout —
#      nên câu hỏi "file .app nằm đâu" không có câu trả lời cố định. Script ghim
#      chỗ đó lại và chép sản phẩm ra một nơi biết trước.
#   2. Bản Release BẮT BUỘC phải universal, và đây là loại lỗi im lặng: bản chỉ
#      có arm64 chạy hoàn hảo trên chính máy vừa dựng nó và chết với mọi người
#      dùng Intel. Phép kiểm ấy phải nằm trong build, không phải nằm trong một
#      danh sách ai đó phải nhớ.

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
Cách dùng: Scripts/build.sh [tuỳ chọn]

Dựng Caffeinate.app, và với bản Release thì kiểm luôn rằng nhị phân là universal
(arm64 + x86_64).

Tuỳ chọn:
  -d, --debug           Cấu hình Debug, chỉ kiến trúc của máy đang ngồi (nhanh hơn)
  -r, --release         Cấu hình Release, universal binary (mặc định)
  -t, --test            Chạy toàn bộ test trước khi dựng
  -T, --test-only       Chỉ chạy test rồi dừng
  -c, --clean           Xoá derived data trước khi dựng
  -o, --output DIR      Nơi đặt Caffeinate.app (mặc định: ./build)
  -q, --quiet           Chỉ hiện cảnh báo, lỗi và kết quả test
  -h, --help            In trợ giúp này

Ví dụ:
  Scripts/build.sh                     # dựng Release vào ./build
  Scripts/build.sh --debug --clean     # dựng Debug từ đầu
  Scripts/build.sh --test-only         # 69 unit test + 9 test giao diện
EOF
}

log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mcảnh báo:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mlỗi:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)     configuration="Debug"; shift ;;
        -r|--release)   configuration="Release"; shift ;;
        -t|--test)      run_tests=true; shift ;;
        -T|--test-only) run_tests=true; build_app=false; shift ;;
        -c|--clean)     do_clean=true; shift ;;
        -o|--output)    [[ $# -ge 2 ]] || die "--output cần một thư mục"
                        output_dir="$2"; shift 2 ;;
        -q|--quiet)     quiet=true; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              usage >&2; die "tuỳ chọn không hiểu: $1" ;;
    esac
done

# Kiểm tra trước khi chạy. `xcodebuild` vẫn tồn tại dưới dạng stub khi máy chỉ
# cài Command Line Tools, và khi đó nó chết muộn kèm một thông báo licence khó
# hiểu — nên phải xác nhận nó thật sự trỏ vào một bản Xcode đầy đủ.
command -v xcodebuild >/dev/null 2>&1 || die "không tìm thấy xcodebuild. Cài Xcode 16 trở lên."
if ! xcodebuild -version >/dev/null 2>&1; then
    die "xcodebuild không dùng được. Trỏ nó vào một bản Xcode đầy đủ:
    sudo xcode-select -s /Applications/Xcode.app"
fi

xcb() {
    if [[ "${quiet}" == true ]]; then
        # xcbeautify/xcpretty không phải phụ thuộc của dự án; thay vào đó lọc
        # thủ công, chỉ giữ chẩn đoán và kết quả. Các mẫu được neo có chủ đích:
        # chữ "warning" trần cũng xuất hiện trong chính các dòng lệnh biên dịch
        # mà xcodebuild in ra (-suppress-warnings, --warnings), và như vậy thì
        # mọi dòng 4 KB đó đều lọt qua.
        #
        # `|| true` nằm TRONG ngoặc để việc grep không tìm thấy gì không che mất
        # mã lỗi của xcodebuild — `set -o pipefail` ở đầu script đưa mã lỗi ấy
        # ra khỏi pipeline.
        xcodebuild "$@" | { grep -E '(^\*\*|: (error|warning): |^Test Case |^Executed |^Testing (failed|succeeded))' || true; }
        return
    fi
    xcodebuild "$@"
}

cd "${REPO_ROOT}"

if [[ "${do_clean}" == true ]]; then
    log "Xoá derived data"
    rm -rf "${DERIVED_DATA}"
    rm -rf "${REPO_ROOT}/CaffeinateKit/.build"
fi

if [[ "${run_tests}" == true ]]; then
    # Test của package là tầng nhanh và tất định — chạy trước để một cái lõi
    # hỏng đỏ trong một giây, thay vì đỏ sau cả một lượt dựng ứng dụng.
    log "Chạy unit test phần lõi (CaffeinateKit)"
    swift test --package-path CaffeinateKit

    log "Chạy test giao diện (chiếm màn hình khoảng một phút)"
    xcb -project "${PROJECT}" \
        -scheme "${SCHEME}" \
        -destination 'platform=macOS' \
        -derivedDataPath "${DERIVED_DATA}" \
        test
fi

if [[ "${build_app}" != true ]]; then
    log "Test xanh"
    exit 0
fi

log "Đang dựng ${SCHEME} (${configuration})"
xcb -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${configuration}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    build

built_app="${DERIVED_DATA}/Build/Products/${configuration}/${SCHEME}.app"
[[ -d "${built_app}" ]] || die "build báo thành công nhưng không thấy ${built_app}"

mkdir -p "${output_dir}"
# Xoá bundle cũ chứ không chép đè: `cp -R` trộn vào thư mục đang có, nên tài
# nguyên thừa từ lần dựng trước có thể còn nằm lại.
rm -rf "${output_dir:?}/${SCHEME}.app"
cp -R "${built_app}" "${output_dir}/"
final_app="${output_dir}/${SCHEME}.app"

binary="${final_app}/Contents/MacOS/${SCHEME}"
architectures="$(lipo -archs "${binary}")"

if [[ "${configuration}" == "Release" ]]; then
    for arch in arm64 x86_64; do
        case " ${architectures} " in
            *" ${arch} "*) ;;
            *) die "bản Release không universal: có '${architectures}', thiếu ${arch}" ;;
        esac
    done
fi

log "Đã dựng ${final_app}"
printf '    cấu hình   : %s\n' "${configuration}"
printf '    kiến trúc  : %s\n' "${architectures}"
printf '    phiên bản  : %s (%s)\n' \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${final_app}/Contents/Info.plist" 2>/dev/null || echo '?')" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${final_app}/Contents/Info.plist" 2>/dev/null || echo '?')"

if [[ "${configuration}" == "Debug" ]]; then
    warn "Bản Debug chỉ có một kiến trúc và không tối ưu. Dùng --release để phát hành."
fi

cat <<EOF

Cài đặt:
    cp -R "${final_app}" /Applications/

Khởi động cùng macOS chỉ hoạt động khi app nằm trong /Applications — đó là yêu
cầu của SMAppService, không phải một tuỳ chọn.
EOF
