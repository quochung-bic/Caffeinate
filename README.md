<img src="Caffeinate/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" align="right" alt="Biểu tượng Caffeinate">

# Caffeinate

Ứng dụng macOS nằm trên thanh menu, giữ cho máy không ngủ khi bạn cần — và tự
tắt khi bạn không cần nữa.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
![Universal](https://img.shields.io/badge/binary-Intel%20%2B%20Apple%20Silicon-black)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![Giấy phép MIT](https://img.shields.io/badge/license-MIT-blue)

Khác với việc kéo thanh trượt trong System Settings rồi quên trả về chỗ cũ,
Caffeinate cho bạn nói rõ **giữ thức cái gì**, **trong bao lâu**, và **khi nào
thì tự bật**. Hết giờ là hết — máy quay lại đúng nếp ngủ mặc định của nó.

---

## Mục lục

- [Tính năng](#tính-năng)
- [Giao diện](#giao-diện)
- [Yêu cầu](#yêu-cầu)
- [Cài đặt](#cài-đặt)
- [Phát triển](#phát-triển)
- [Kiến trúc](#kiến-trúc)
- [Hiện chưa có](#hiện-chưa-có)
- [Giấy phép](#giấy-phép)

---

## Tính năng

### Chọn đúng thứ cần giữ

Bốn khía cạnh bật/tắt độc lập, mỗi cái là một power assertion riêng của IOKit:

| Cờ | Giữ điều gì |
|---|---|
| Hệ thống | Máy không vào chế độ ngủ |
| Màn hình | Màn hình không tắt |
| Đĩa | Ổ đĩa không ngủ |
| Idle | Hệ thống không tính bạn là "đang rảnh" |

Mặc định chỉ bật **Hệ thống**. Giữ màn hình sáng tốn pin và hiếm khi thật sự
cần, nên đó phải là thứ bạn chủ động chọn chứ không phải thứ ứng dụng tự quyết
hộ.

### Hẹn giờ có điểm dừng

Bấm một nút để chạy 15 phút, 30 phút, 1 giờ, một mốc tùy chỉnh của riêng bạn
(1–480 phút), hoặc bật không giới hạn.

Khi hết giờ, Caffeinate báo bằng **ba đường độc lập** — banner thông báo, một
tiếng chuông, và icon menu bar nhấp nháy — vì đường nào cũng có lúc câm: banner
bị Do Not Disturb chặn, âm thanh vô nghĩa khi tai nghe đang ở phòng khác, còn
icon thì chỉ thấy nếu đang nhìn lên thanh menu.

### Tự bật theo hoàn cảnh

Ba luật, bật cái nào tùy bạn:

- một app trong danh sách bạn chọn đang chạy (ví dụ máy ảo, phần mềm render,
  trình biên dịch);
- máy đang cắm sạc;
- có màn hình ngoài đang cắm.

Luật tự động không giành quyền với bạn: nút **Tắt** là dứt khoát, nó gỡ cả những
luật đang đúng. Một luật chỉ bật trở lại khi điều kiện của nó thật sự tái diễn —
rút sạc rồi cắm lại, chứ không phải vài giây sau khi hệ thống gửi thêm một thông
báo "vẫn đang sạc".

### Nhìn là biết

Biểu tượng chủ đạo là một ly cà phê mà **mực nước chính là thanh tiến trình**:
đầy khi vừa bật, vơi dần theo đồng hồ đếm ngược, và chỉ bốc hơi khi máy thật sự
đang được giữ thức. Cùng một hình đó xuất hiện hai nơi — lớn trong panel, và thu
nhỏ 18×18 làm icon trên thanh menu.

### Song ngữ, đổi được ngay trong app

Giao diện có tiếng Việt và tiếng Anh. Mặc định đi theo ngôn ngữ hệ thống, nhưng
bạn đổi được riêng cho Caffeinate ở **Cài đặt → Chung → Ngôn ngữ**, và nó đổi
ngay — không phải khởi động lại app.

Các hộp thoại do macOS vẽ hộ (chọn app, xin quyền thông báo) đổi từ lần mở app
sau, vì bundle chỉ nạp danh sách ngôn ngữ một lần lúc khởi động.

### Khởi động cùng macOS

Đăng ký qua `SMAppService`, mặc định tắt. Có thêm tùy chọn bật sẵn ngay khi app
khởi chạy, chỉ dùng được khi khởi động cùng hệ thống đã bật — vì nếu app không
tự chạy lúc đăng nhập thì tùy chọn kia chẳng có tác dụng gì.

---

## Giao diện

Caffeinate là ứng dụng thanh menu thuần: **không có icon Dock, không có cửa sổ
chính**. Đó là quyết định kiến trúc chứ không phải lựa chọn thẩm mỹ — icon trên
thanh menu là bề mặt duy nhất luôn tồn tại, nên mọi thứ phải sống suốt phiên đều
móc vào đó.

- **Panel trên thanh menu** — bấm icon là có ngay ly cà phê đếm ngược, các nút
  thời lượng, trạng thái bốn cờ và lý do đang bật.
- **Cửa sổ Cài đặt** (⌘,) — bốn tab: *Chung*, *Tự động*, *Khởi động*,
  *Giới thiệu*. Đóng bằng ⌘W, thoát app bằng ⌘Q.

---

## Yêu cầu

- macOS 14 (Sonoma) trở lên — chạy trên cả máy Intel lẫn Apple Silicon
- Xcode 16 trở lên (Swift 6) để build

---

## Cài đặt

Chưa có bản dựng phát hành sẵn — hiện tại bạn tự build từ mã nguồn:

```bash
git clone https://github.com/quochung-bic/Caffeinate.git
cd Caffeinate
./Scripts/install.sh
```

`install.sh` dựng bản Release, bảo bản đang chạy thoát, thay
`/Applications/Caffeinate.app` rồi mở app lên. Chạy lại đúng lệnh đó mỗi khi
muốn cập nhật. `--test` để chạy toàn bộ test trước, `--destination` để cài chỗ
khác (xem cảnh báo ở cuối mục này), `--help` để xem hết tuỳ chọn.

Vì bạn tự biên dịch nên bundle không mang cờ quarantine: Gatekeeper không chặn
và cũng không hỏi gì — thứ khác hẳn với một file `.app` tải từ trên mạng về.
Chữ ký là ad-hoc, đủ để chạy trên máy của chính bạn; muốn phát cho người khác
tải về thì cần Developer ID và notarize.

Gỡ cài đặt: thoát app từ thanh menu rồi kéo `Caffeinate.app` vào Thùng rác. Thứ
duy nhất nó để lại là `~/Library/Preferences/io.github.quochung-bic.Caffeinate.plist`.

### Chỉ dựng, không cài

```bash
./Scripts/build.sh
```

Sản phẩm nằm ở `build/Caffeinate.app`, và script kiểm luôn rằng bản Release
đúng là universal binary. Thêm `--debug` để dựng nhanh cho máy đang ngồi,
`--test` để chạy test trước, `--help` để xem hết tuỳ chọn.

Hoặc gọi `xcodebuild` trực tiếp:

```bash
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' -configuration Release build
```

Bản Release luôn dựng universal binary (arm64 + x86_64). Kiểm chứng:

```bash
lipo -info /đường/dẫn/tới/Caffeinate.app/Contents/MacOS/Caffeinate
# Architectures in the fat file: ... are: x86_64 arm64
```

Dựng bằng tay thì nhớ chép `Caffeinate.app` vào `/Applications` — đó là việc
`install.sh` làm hộ. Bước chép này không chỉ cho gọn: **tính năng khởi động cùng
macOS chỉ hoạt động khi app nằm trong `/Applications`**, vì `SMAppService` từ
chối đăng ký bundle nằm chỗ khác. Chạy từ `build/` hay từ `~/Applications` thì
mọi thứ khác vẫn đúng, riêng công tắc ấy sẽ báo lỗi và nói rõ lý do.

Hoặc mở `Caffeinate.xcodeproj` bằng Xcode rồi bấm Run như bình thường.

---

## Phát triển

```bash
# build từ dòng lệnh (xem `--help` để biết hết tuỳ chọn)
./Scripts/build.sh

# 69 unit test của phần lõi — nhanh, không cần GUI
swift test --package-path CaffeinateKit

# chạy một suite hoặc một test lẻ
swift test --package-path CaffeinateKit --filter 'CaffeineController'

# build ứng dụng
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' build

# build + 9 test giao diện: smoke, chuyển ngữ, nhãn trợ năng (~1 phút)
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' test

# vẽ lại toàn bộ bộ icon ứng dụng
swift Scripts/GenerateAppIcon.swift
```

Cài đặt build nằm trong [`Configs/`](Configs/), không nằm trong
`project.pbxproj` — mỗi lựa chọn đều có chú thích giải thích vì sao.

Chi tiết kiến trúc, các bất biến và những chỗ dễ vấp:
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Kiến trúc

Phần lõi nằm trong một SwiftPM package tách rời, phần app chỉ còn giao diện và
dây nối:

```
CaffeinateKit/          gói Swift thuần — toàn bộ logic, không GUI, không chuỗi hiển thị
  Core/                 AssertionFlags, AssertionManager, IOKitBacking
  State/                CaffeineEvent, CaffeineState, reduce
  Triggers/             app đang chạy, cắm sạc, màn hình ngoài
  Storage/              lưu cài đặt vào UserDefaults
  Rendering/            vẽ icon menu bar (AppKit)
  CaffeineController    nguồn sự thật cho UI
Caffeinate/             app target — SwiftUI + vòng đời ứng dụng
  MenuBar/              nhãn trên thanh menu và panel điều khiển
  Settings/             cửa sổ Cài đặt, bốn tab
  Components/           ly cà phê, hàng nút thời lượng, lưới cờ
  Services/             khởi động cùng macOS, báo hết giờ
  Localization/         String Catalog + cầu nối kiểu → câu chữ
Configs/                cài đặt build (.xcconfig) và entitlements
Scripts/                script build và sinh icon ứng dụng
CaffeinateUITests/      test giao diện — smoke, chuyển ngữ, nhãn trợ năng
```

Bốn nguyên tắc được giữ nghiêm ngặt xuyên suốt:

**Một đường thay đổi trạng thái duy nhất.** `CaffeineController` là nơi *duy
nhất* gọi `AssertionManager.set(flags:)`. Mọi thay đổi đều đi `send(event) →
reduce() → apply()`. Không có lối tắt nào, nên trạng thái thật của hệ thống luôn
suy ra được từ trạng thái trong app.

**Phân tầng rõ.** Package không bao giờ import SwiftUI; `Core/` và `State/`
không import AppKit; app target không import IOKit. Toàn bộ IOKit gói gọn trong
hai file: `IOKitBacking.swift` và `PowerSourceTrigger.swift`.

**Lõi không biết tiếng nào.** `CaffeinateKit` không chứa một chuỗi giao diện
nào. Nó trả về kiểu dữ liệu; tầng app dịch chúng qua String Catalog. Nhờ vậy
thêm một ngôn ngữ không phải sửa một dòng nào trong lõi.

**Không chỗ nào được hỏng im lặng.** Tạo assertion lỗi thì ném lỗi và ép trạng
thái về tắt — không giả vờ đang bật. Lỗi lúc giải phóng được ghi lại và hiển thị
cho người dùng thấy, chứ không nuốt.

---

## Hiện chưa có

- **Ký Developer ID và notarize.** Máy khác mở lần đầu sẽ bị Gatekeeper chặn
  (chuột phải → Open để bỏ qua).
- **Bản dựng phát hành sẵn** để tải về.
- **Định dạng `.icon` của Icon Composer** cho macOS 26. Bộ `.appiconset` hiện
  tại hiển thị đúng trên macOS 14, 15 và 26, nhưng chưa nhận hiệu ứng Liquid
  Glass của Tahoe. Việc này cần ứng dụng GUI Icon Composer.
- **Tích hợp liên tục (CI).**

---

## Giấy phép

[MIT](LICENSE) © 2026 Quốc Hưng
