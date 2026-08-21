# CLAUDE.md

Hướng dẫn cho Claude Code khi làm việc trong repo này.

## Ngôn ngữ

Mã nguồn, chú thích và tài liệu **viết bằng tiếng Việt**. Giữ nguyên quy ước
này. Ngoại lệ duy nhất là những chuỗi mà hệ điều hành đọc (xem *Bất biến* bên
dưới).

**Thông điệp commit viết bằng tiếng Anh** — câu mệnh lệnh tự nhiên, dòng đầu
không quá 60 ký tự, không dùng prefix `feat:`/`fix:`. Phần thân giải thích *vì
sao*, không nhắc lại *cái gì*.

## Lệnh hay dùng

```bash
# build từ dòng lệnh — Release, kiểm luôn universal binary, ra ./build/Caffeinate.app
./Scripts/build.sh            # --debug nhanh hơn, --test chạy test trước, --help xem hết

# unit test phần lõi — 69 test, chưa tới 0,2 s, không cần GUI. Chạy cái này trước.
swift test --package-path CaffeinateKit

# chạy một suite hoặc một test lẻ (khớp theo tên hiển thị tiếng Việt)
swift test --package-path CaffeinateKit --filter 'CaffeineController'
swift test --package-path CaffeinateKit --filter 'hẹn giờ'

# build ứng dụng
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' build

# build + toàn bộ test giao diện (chậm, ~1 phút, chiếm màn hình)
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' test

# chạy một lớp / một test giao diện lẻ
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' \
           -only-testing:CaffeinateUITests/SettingsAccessibilityTests test

# vẽ lại toàn bộ bộ icon ứng dụng
swift Scripts/GenerateAppIcon.swift

# kiểm chứng bản Release là universal binary
lipo -info <đường-dẫn>/Caffeinate.app/Contents/MacOS/Caffeinate
```

Đích cuối phải luôn xanh: **69 unit test + 9 test giao diện, không cảnh báo nào**.

Chín test giao diện chia làm ba nhóm, và nhóm nào đỏ cũng nói lên chuyện khác nhau:

| Lớp | Số test | Bắt được gì |
|---|---|---|
| `SmokeTests` | 2 | nút → controller → state, và giao diện ra đúng tiếng Anh |
| `LocalizationTests` | 4 | lựa chọn ngôn ngữ trong app thắng hệ thống; không khoá nào lọt khỏi catalog; không khoá nào thiếu bản tiếng Anh |
| `SettingsAccessibilityTests` | 3 | mọi control trong cửa sổ Cài đặt có nhãn trợ năng |

Cả ba đều chốt ngôn ngữ bằng `-AppleLanguages` và bật app bằng
`-CaffeinateUITesting` (nâng app từ `LSUIElement` lên `.regular` rồi mở
`UITestHarnessWindow`). Thêm `-CaffeinateUITestSurface settings` thì cửa sổ host
dựng thẳng `SettingsView` — đó là cách duy nhất chạm được vào `Settings` scene
từ XCUITest.

## Bố cục

| Đường dẫn | Chứa gì |
|---|---|
| `CaffeinateKit/` | SwiftPM package — toàn bộ logic. Không GUI, không chuỗi hiển thị. |
| `Caffeinate/` | App target (SwiftUI). Thư mục đồng bộ hệ thống tệp: thêm file là Xcode tự nhận, **không cần sửa `project.pbxproj`**. |
| `Configs/` | Cài đặt build (`.xcconfig`) và entitlements. Sửa build settings ở đây, không sửa trong pbxproj. |
| `Scripts/` | `build.sh` (build từ dòng lệnh) và `GenerateAppIcon.swift` — icon ứng dụng là mã nguồn, không phải file nhị phân chép tay. |
| `CaffeinateUITests/` | Test giao diện — smoke, chuyển ngữ, nhãn trợ năng. |
| `docs/ARCHITECTURE.md` | Kiến trúc chi tiết, các bất biến, những chỗ dễ vấp. |

Luồng dữ liệu chỉ có một chiều, và mọi thứ đều bám vào `CaffeineController`:

```
MenuBarLabel / ControlPanel / SettingsView   ← đọc @Observable
TriggerEngine (app đang chạy · cắm sạc · màn hình ngoài)
              ↓ send(event)
        CaffeineController  →  reduce()  →  apply()  →  AssertionManager  →  IOKit
```

`project.pbxproj` được viết tay và cố ý giữ tối giản. Tránh mở project bằng
Xcode rồi lưu lại — Xcode sẽ viết đè và làm phình file.

## Bất biến — đừng phá

1. **Một đường thay đổi trạng thái duy nhất.** `CaffeineController` là nơi *duy
   nhất* gọi `AssertionManager.set(flags:)`. Mọi thay đổi đi qua
   `send(event) → reduce() → apply()`.

2. **`reduce` là hàm thuần tuý.** Không I/O, không đọc đồng hồ hệ thống. Mọi mốc
   thời gian đi vào qua sự kiện.

3. **`CaffeinateKit` không chứa chuỗi giao diện.** Trả về kiểu dữ liệu; tầng app
   dịch trong `Caffeinate/Localization/`. Thêm một chuỗi tiếng Việt vào package
   là phá bản dịch tiếng Anh.

4. **`AssertionManager.defaultReason` phải thuần ASCII và không được dịch.** Đó
   là chuỗi `pmset -g assertions` in ra; chữ có dấu làm assertion thành vô danh.

5. **Phân tầng import.** Package không import SwiftUI. `Core/` và `State/` không
   import AppKit. App target không import IOKit.

6. **Nút Tắt là dứt khoát.** `stopAll` xoá cả lý do trigger đang đúng, nhưng
   *không* reset baseline nội bộ của trigger. Đọc chú thích dài trong
   `CaffeineController.toggle()` và `PowerSourceTrigger.refresh()` trước khi
   động vào — đã có người "sửa" chỗ này và làm hỏng hành vi.

7. **Không chỗ nào được hỏng im lặng.** Create lỗi → ép về tắt + báo. Release
   lỗi → giữ nguyên trạng thái + báo. Không nuốt lỗi nào.

## Những chỗ dễ vấp

- **`Settings` có hai nghĩa.** `CaffeinateKit.Settings` (cấu hình người dùng) và
  `SwiftUI.Settings` (scene). Trong `CaffeinateApp.swift` phải viết
  `SwiftUI.Settings { … }`, nếu không trình biên dịch báo lỗi ở một chỗ hoàn
  toàn khác với "failed to produce diagnostic".

- **XCUITest không chịu được nhịp chạy nền.** Khi đang đếm ngược, nhãn menu bar
  chạy `TimelineView` 1 Hz và XCUITest không bao giờ thấy app "đứng yên" → mọi
  truy vấn hết giờ chờ. Đừng thêm UI test cho chế độ đếm ngược; phủ nó ở
  `CaffeineControllerTimerTests`.

- **App là `LSUIElement`.** Không có icon Dock, không có cửa sổ chính, và không
  sở hữu thanh menu hệ thống — nên ⌘W phải tự gắn lại bằng nút ẩn
  (`CloseWindowShortcut`). UI test chạy được nhờ cờ `-CaffeinateUITesting` nâng
  app lên `.regular` và mở `UITestHarnessWindow`.

- **Nhãn trợ năng không được đổi mỗi giây.** Nhãn của `CoffeeGauge` nói mốc kết
  thúc ("hẹn giờ tới 15:47") chứ không nói thời gian còn lại, để nó đứng yên.
  Đổi lại thành đếm ngược sẽ làm VoiceOver đọc lặp và làm hỏng UI test.

- **`TimelineView` không chạy nhịp trong nhãn `MenuBarExtra`.** Đã đo: 2 lần vẽ
  lại trong 8 giây. Nhãn phải đọc `controller.now` (thuộc tính `@Observable`
  thật sự thay đổi) thì icon mới vơi dần. Đừng "dọn dẹp" bằng cách thay lại
  bằng `TimelineView`.

- **`Toggle`/`Picker`/`Stepper` trong `Form` trên macOS KHÔNG có nhãn trợ năng.**
  Nhãn được vẽ thành một dòng chữ riêng cạnh control chứ không gắn vào control,
  nên VoiceOver đọc ra toàn "switch, off". Mọi control trong cửa sổ Cài đặt phải
  có `.accessibilityLabel(…)` gắn tay, kể cả khi nhãn đã khai báo bằng chuỗi
  thuần. `SettingsAccessibilityTests` bắt được chuyện này.

- **`MenuBarIconState` lượng tử hoá tiến trình về 32 bậc** để làm khoá cache
  dùng được. Bỏ lượng tử hoá là vô hiệu hoá cache.

- **Đổi chuỗi giao diện thì phải cập nhật `Localizable.xcstrings` bằng tay.**
  Thêm một `Text("…")` mới mà quên khai báo thì build KHÔNG cảnh báo gì, khoá
  biến mất khỏi mọi bảng chuỗi, và người dùng tiếng Anh thấy tiếng Việt.
  `LocalizationTests` bắt được cả chuyện đó lẫn chuyện quên dịch — chạy
  `xcodebuild … test` trước khi coi là xong.
  (`-exportLocalizations` chỉ đọc lại catalog, KHÔNG trích xuất lại từ mã, nên
  đừng dùng nó để tìm khoá mới.)

- **Chuỗi nào chỉ hiện với người dùng thì phải đi qua `\.locale`.**
  `String(localized:locale:)` KHÔNG dùng tham số `locale` để chọn bảng chuỗi —
  chỉ để chọn luật số nhiều. Dùng nó là được một app đổi nút mà không đổi thông
  báo. Trong view thì dùng `Text("literal")` (theo environment) hoặc
  `resource.text(in: locale)`; ngoài view thì `LanguagePreference.resolve(_:)`.

- **`.gitignore` chạy theo lối whitelist.** Dòng `/*` chặn sạch thư mục gốc,
  bên dưới mới mở lại từng mục một. Hệ quả: thêm một thư mục mới ở gốc mà quên
  khai báo `!/tên/` thì `git status` KHÔNG hiện gì cả — file mới im lặng nằm
  ngoài repo. Đổi lại, không có rác nào của công cụ tự chui vào commit. Bên
  trong các thư mục đã mở lại thì whitelist hết tác dụng, nên `.build/`,
  `DerivedData/`, `xcuserdata/` vẫn phải nêu tên riêng.

## Quy ước viết mã

- Chú thích giải thích **vì sao**, không phải **cái gì**. Chỗ nào có quyết định
  đánh đổi hoặc một cái bẫy đã vấp qua thì viết ra, kể cả dài.
- Tên test viết bằng tiếng Việt, mô tả hành vi chứ không mô tả hàm được gọi.
- Không thêm phụ thuộc bên thứ ba. Dự án cố ý chỉ dùng thư viện hệ thống.
