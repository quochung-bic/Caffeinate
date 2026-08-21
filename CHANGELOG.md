# Nhật ký thay đổi

Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/),
đánh số theo [Semantic Versioning](https://semver.org/lang/vi/).

## [Chưa phát hành]

### Thêm

- Giao diện song ngữ tiếng Việt và tiếng Anh (String Catalog, 80 khoá, có dạng
  số nhiều thật cho tiếng Anh).
- **Đổi ngôn ngữ ngay trong app** ở Cài đặt › Chung › Ngôn ngữ: Theo hệ thống /
  Tiếng Việt / English. Giao diện đổi tức thì, không cần khởi động lại; các hộp
  thoại do macOS vẽ hộ đổi từ lần mở app sau.
- Cửa sổ Cài đặt chuẩn macOS (⌘,) chia bốn tab: Giữ thức, Tự động, Khởi động,
  Giới thiệu. Đóng được bằng ⌘W.
- `Scripts/GenerateAppIcon.swift` — sinh toàn bộ bộ icon ứng dụng từ mã.
- `Scripts/build.sh` — build từ dòng lệnh, đặt sản phẩm ở một chỗ cố định
  (`build/Caffeinate.app`) và **chặn bản Release không universal**, thay vì để
  chuyện đó thành một mục trong danh sách phải nhớ.
- `Scripts/install.sh` — dựng rồi đặt vào `/Applications` bằng một lệnh, cho
  người vừa clone repo về. Nó lo ba việc mà một dòng `cp -R` bỏ sót: bảo bản
  đang chạy thoát để nó kịp ghi cài đặt và nhả assertion, thay hẳn bundle cũ
  thay vì trộn vào nó, và mở app lên — với một app thanh menu thuần thì chép
  xong chẳng có gì hiện ra để biết là đã cài được.
- `.gitignore` chuyển sang lối whitelist: chặn hết ở gốc rồi mở lại đúng những
  thư mục thuộc về dự án, để rác của công cụ không lọt vào commit chỉ vì chưa
  ai gặp nó bao giờ.
- Cài đặt build tách ra `Configs/*.xcconfig`, có chú thích cho từng lựa chọn.
- 23 unit test mới cho lược đồ cài đặt, ưu tiên trigger, hẹn giờ và trạng thái
  icon (46 → 69), cùng 5 test giao diện cho phần chuyển ngữ: lựa chọn trong app
  thắng ngôn ngữ hệ thống (cả hai chiều), không chuỗi nào trong mã bị bỏ quên
  khỏi catalog, và không khoá nào thiếu bản dịch tiếng Anh.
- 3 test giao diện cho cửa sổ Cài đặt, vốn trước đó không có test nào: mọi
  control phải có nhãn trợ năng, bốn cờ phải nhận ra được từng cái, và cửa sổ
  phải đổi ngôn ngữ theo. `UITestHarnessWindow` nhận thêm cờ
  `-CaffeinateUITestSurface settings` để mở được cửa sổ đó từ test.

### Thay đổi

- **Caffeinate trở thành ứng dụng thanh menu thuần** (`LSUIElement`): không còn
  icon Dock và không còn cửa sổ chính. Toàn bộ điều khiển nằm trong panel trên
  thanh menu; cấu hình nằm ở cửa sổ Cài đặt.
- Icon ứng dụng vẽ lại: nền gradient nâu ấm, ly sứ nét dày, đúng lưới icon
  macOS (thân 824 trong khung 1024) và góc bo siêu ellipse.
- `CaffeinateKit` không còn chứa chuỗi giao diện nào. Lỗi trở thành
  `AssertionFailure` có kiểu, phân biệt "không giữ được" với "không gỡ được".
- Thứ tự ưu tiên khi nhiều luật tự động cùng đúng nay là `Comparable` tường
  minh thay vì sắp xếp theo chuỗi tiếng Việt — đổi ngôn ngữ không còn lặng lẽ
  đổi lý do được hiển thị.
- `bundle identifier` đổi thành `io.github.quochung-bic.Caffeinate`. Bản dựng
  mới không đọc được cài đặt của bản cũ (`com.caffeinate.app`).
- Bản Release không còn tiêm entitlement `get-task-allow`.

### Sửa

- **Mọi control trong cửa sổ Cài đặt đều không có nhãn trợ năng.** Chín công
  tắc, một menu chọn và một stepper đọc ra với VoiceOver chỉ là "switch, off" —
  không phân biệt được cái nào với cái nào. Nguyên nhân: trong `Form` trên
  macOS, nhãn được vẽ cạnh control chứ không gắn vào control, kể cả khi khai
  báo bằng chuỗi thuần.
- Hai nhánh `default: ""` trong cầu nối chuyển ngữ sinh ra một khoá dịch RỖNG
  trong catalog. Do chính test mới phát hiện.

- Móc vòng đời (`willTerminate`) đăng ký không idempotent: mỗi lần SwiftUI dựng
  lại nhãn menu bar là thêm một observer, nên `shutdown()` chạy nhiều lần lúc
  thoát. Quan sát nay theo kiểu RAII, tự gỡ khi hết vòng đời.
- Cài đặt bị xoá sạch khi thiếu một khoá: `Codable` sinh tự động ném lỗi và
  store rơi về mặc định. Nay giải mã khoan dung theo từng khoá, kèm chuẩn hoá
  giá trị (kẹp thời lượng, loại bundle ID trùng/rỗng).
- Phần tử trợ năng của ly cà phê bị dựng lại 24 lần mỗi giây, làm VoiceOver mất
  chỗ bám. Nay nhãn đứng yên suốt lần hẹn giờ (nói mốc kết thúc thay vì thời
  gian còn lại).

### Hiệu suất

- Ly cà phê và số đếm ngược nay chỉ tồn tại khi panel đang mở, thay vì chạy
  liên tục trong một cửa sổ chính luôn mở. Ở trạng thái thường trực, app không
  vẽ gì cả.
- Phần tính trạng thái icon trở thành thuần tuý (`iconState(at: Date)`), test
  được mà không cần chờ đồng hồ thật. Nhịp 1 Hz vẫn do controller phát nhưng
  chỉ sống khi `timerEndsAt != nil` — bắt buộc phải như vậy, vì đo được rằng
  `TimelineView` không chạy nhịp bên trong nhãn `MenuBarExtra`.
- `MenuBarIconState` lượng tử hoá tiến trình về 32 bậc (dưới ngưỡng một pixel ở
  18pt) và `MenuBarIcon` có cache: một lần hẹn giờ 8 tiếng dựng 32 tấm ảnh thay
  vì 28.800.
- Ly cà phê hạ từ 24 xuống 20 fps và tách khỏi phần đếm ngược 1 Hz, nên mỗi
  thành phần chỉ vẽ đúng nhịp nó cần.
