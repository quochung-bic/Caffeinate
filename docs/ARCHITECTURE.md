# Kiến trúc

Tài liệu này giải thích *vì sao* Caffeinate được dựng như hiện tại. Phần *cái
gì* nằm trong [README](../README.md); phần hướng dẫn thao tác nằm trong
[CLAUDE.md](../CLAUDE.md).

## Toàn cảnh

```
                       ┌─────────────────────────────┐
   thanh menu ────────▶│      MenuBarLabel           │
                       │  (nhịp 1 Hz khi đếm ngược)  │
                       └──────────────┬──────────────┘
                                      │ đọc
   panel  ────────────▶ ControlPanel ─┤
   ⌘,     ────────────▶ SettingsView ─┤
                                      ▼
                       ┌─────────────────────────────┐
                       │     CaffeineController      │  @MainActor @Observable
                       │  send(event) → reduce → apply
                       └──────┬───────────────┬──────┘
                              │               │
                   ┌──────────▼──────┐  ┌─────▼────────────┐
                   │ AssertionManager│  │  TriggerEngine   │
                   └────────┬────────┘  └─────┬────────────┘
                            │                 │
                   ┌────────▼────────┐  ┌─────▼──────────────────────────┐
                   │  IOKitBacking   │  │ AppRunning / PowerSource /     │
                   │   (IOKit pwr)   │  │ ExternalDisplay                │
                   └─────────────────┘  └────────────────────────────────┘
```

## Vì sao lõi là một package riêng

`CaffeinateKit` không phải là chia nhỏ cho có. Nó tạo ra một ranh giới mà trình
biên dịch ép buộc được: package không thể import SwiftUI, nên không có cách nào
để logic trạng thái lén phụ thuộc vào một `@State` nào đó. Hệ quả thực tế là
`swift test` chạy 69 test trong chưa tới một phần mười giây mà không cần dựng
ứng dụng, không cần GUI, và không cần đụng vào hệ thống thật.

Ranh giới ấy chỉ có giá trị nếu được giữ. Ba luật:

- Package không import SwiftUI.
- `Core/` và `State/` không import AppKit.
- App target không import IOKit.

## Vì sao chỉ một đường thay đổi trạng thái

`CaffeineController` là nơi duy nhất gọi `AssertionManager.set(flags:)`. Mọi
thay đổi đi qua `send(event) → reduce() → apply()`.

Điều này đắt hơn việc gọi thẳng, và nó đáng giá vì một lý do cụ thể: assertion
IOKit là tài nguyên *ngoài* tiến trình. Nếu có hai đường ghi, sẽ có lúc trạng
thái trong app và trạng thái thật của hệ thống lệch nhau, và không ai biết cái
nào đúng. Với một đường duy nhất, `state.effectiveFlags` *là* định nghĩa của
những gì hệ thống đang giữ.

`reduce` thuần tuý — không I/O, không đọc `Date()`. Mọi mốc thời gian đi vào qua
sự kiện (`.startedTimer(until:)`). Nhờ vậy mọi chuyển tiếp trạng thái đều test
được mà không cần chờ đồng hồ thật chạy.

## Vì sao lõi không biết tiếng nào

Ban đầu `AssertionFlags` có `displayName` trả về `"Hệ thống"`. Nó tiện, và nó
sai theo hai cách:

1. Package bị khoá vào một ngôn ngữ. Thêm tiếng Anh sẽ phải sửa lõi.
2. Nó lặng lẽ chui vào logic. `CaffeineState.activeReason` chọn lý do hiển thị
   bằng cách **sắp xếp theo chuỗi tiếng Việt** — nghĩa là đổi ngôn ngữ giao diện
   sẽ đổi luôn lý do nào được hiển thị. Một bug không ai đoán ra được cho tới
   khi nó xảy ra.

Nay package trả về dữ liệu (`AssertionFlags.identifier`, `TriggerReason`,
`AssertionFailure`) và `Caffeinate/Localization/CaffeinateKit+Localized.swift`
là chỗ duy nhất biến chúng thành câu chữ. Thứ tự ưu tiên trigger là một
`Comparable` tường minh, độc lập ngôn ngữ.

Ngoại lệ duy nhất: `AssertionManager.defaultReason`. Đó không phải chuỗi giao
diện mà là chuỗi hệ điều hành đọc — nó hiện ra trong `pmset -g assertions`. Phải
thuần ASCII (chữ có dấu làm assertion thành vô danh) và không bao giờ dịch.

## Đổi ngôn ngữ trong app hoạt động thế nào

macOS đã có sẵn cơ chế chọn ngôn ngữ theo từng app (System Settings › General ›
Language & Region › Applications), nhưng nó bị chôn sâu tới mức phần lớn người
dùng không biết là có. Caffeinate đưa lựa chọn đó vào Cài đặt › Chung.

Có hai kênh, và chúng lo hai phần khác nhau:

| Kênh | Đổi cái gì | Khi nào có hiệu lực |
|---|---|---|
| `EnvironmentValues.locale` bơm vào gốc mỗi scene | mọi thứ do app tự vẽ | ngay lập tức |
| `AppleLanguages` ghi vào miền UserDefaults của app | hộp thoại do macOS vẽ hộ | từ lần mở app sau |

Kênh thứ hai chính là cơ chế mà System Settings dùng, nên hai nơi không đánh
nhau. Kênh thứ nhất là thứ làm cho việc đổi ngôn ngữ không cần khởi động lại —
đã đo: ép `.environment(\.locale, "en")` trong khi tiến trình chạy tiếng Việt
thì nhãn nút ra tiếng Anh ngay.

### Cái bẫy: `String(localized:locale:)` không làm việc bạn tưởng

Tham số `locale` của `String(localized:)` **không** dùng để chọn bảng chuỗi. Nó
chỉ chọn luật số nhiều; bảng thì vẫn lấy theo ngôn ngữ của tiến trình. Đã đo:
gọi với `locale: "vi"` trên một máy chạy tiếng Anh vẫn trả về `"Stop"`, và tệ
hơn, nó ghép luật số nhiều tiếng Việt (chỉ có dạng `other`) vào câu tiếng Anh,
cho ra `"1 minutes left"`.

Dùng nó cho phần chuyển ngữ sẽ ra một app đổi được nút nhưng không đổi được
thông báo. Cách đúng cho các chuỗi ngoài SwiftUI là `LocalizedStringResource` có
gán `locale` — cái đó chọn bảng thật. Vì vậy:

- trong view, chuỗi literal đi qua `Text("…")` (SwiftUI tra theo environment);
- chuỗi đến từ `CaffeinateKit` đi qua `resource.text(in: locale)`;
- ngoài view (thông báo, nhãn VoiceOver của icon menu bar) đi qua
  `LanguagePreference.resolve(_:)`.

### Ba lớp test giữ cho bản dịch không mục

`LocalizationTests` khoá lại ba thứ khác nhau, và mỗi cái từng thật sự đỏ trong
lúc dựng tính năng này:

1. **Lựa chọn trong app thắng ngôn ngữ hệ thống** — chạy app với
   `-AppleLanguages (vi)` nhưng `-preferredLanguage en`, và ngược lại.
2. **Không chuỗi nào trong mã bị bỏ quên khỏi catalog.** Đối chiếu các file
   `.stringsdata` trình biên dịch sinh ra với bảng tiếng Việt. Cần thiết vì
   thiếu khai báo thì build không cảnh báo gì cả — khoá đơn giản là biến mất
   khỏi mọi bảng, và SwiftUI hiển thị luôn chuỗi tiếng Việt viết trong mã.
   Test này bắt được một khoá RỖNG ngay lần chạy đầu tiên, sinh ra từ một nhánh
   `default: ""`.
3. **Không khoá nào trong catalog thiếu bản dịch tiếng Anh.** Đối chiếu bảng
   tiếng Việt với bảng tiếng Anh trong app bundle đã biên dịch.

Cách kiểm tra ở mục 3 được chọn sau khi cách hiển nhiên hơn tỏ ra vô dụng: ban
đầu test đi tìm những khoá mà bản tiếng Anh trùng bản gốc. Thử gỡ hẳn một bản
dịch rồi chạy lại thì test vẫn xanh — trình biên dịch String Catalog không ghi
khoá chưa dịch vào `en.lproj` chút nào. Một test không bao giờ đỏ được thì không
bảo vệ được gì, nên cả ba lớp trên đều đã được kiểm chứng bằng cách cố tình làm
hỏng rồi xem nó có đỏ không.

## Nhãn trợ năng trong cửa sổ Cài đặt phải gắn tay

Trong `Form` trên macOS, nhãn của `Toggle`, `Picker` và `Stepper` được vẽ thành
một dòng chữ RIÊNG nằm cạnh control chứ không gắn vào chính control. Hệ quả:
VoiceOver đọc ra chín cái công tắc giống hệt nhau — "switch, off" — không phân
biệt được cái nào là "Màn hình" và cái nào là "Đang cắm sạc".

Điều này đúng kể cả khi nhãn được khai báo bằng chuỗi thuần
(`Toggle("Đang cắm sạc", isOn:)`), nên nó không phải hậu quả của việc dùng
`VStack` làm nhãn. Mọi control trong cửa sổ Cài đặt đều phải có
`.accessibilityLabel(…)` gắn tay.

Lỗi này tồn tại được vì cửa sổ Cài đặt là một `Settings` scene mà XCUITest không
mở được từ ngoài — tức là phần đó của app không có test nào. Cách sửa gốc không
phải là nhớ kỹ hơn mà là làm cho nó test được: `UITestHarnessWindow` nhận thêm
cờ `-CaffeinateUITestSurface settings` để host chính `SettingsView`, và
`SettingsAccessibilityTests` đi qua từng tab kiểm tra rằng không control nào có
nhãn rỗng. Test đó phát hiện ra hai tab còn lại cũng hỏng y hệt.

## Vì sao app không có cửa sổ chính

Bản đầu có cửa sổ chính ba tab bên cạnh panel menu bar. Gần như toàn bộ độ phức
tạp vòng đời của app nằm ở việc điều phối hai thứ đó:

- một `NSApplicationDelegate` đoán xem lúc khởi động có nên mở cửa sổ không —
  và câu trả lời khác nhau tuỳ app được mở bằng tay, bởi login item, hay bằng
  cách bấm icon menu bar;
- một bộ theo dõi `NSWindow.didBecomeKeyNotification` lọc ra `NSPanel` để đóng
  cửa sổ chính khi panel bật lên;
- một bộ đếm yêu cầu mở cửa sổ, vì dùng cờ `Bool` thì hai yêu cầu liên tiếp nuốt
  mất cái thứ hai.

`LSUIElement = YES` xoá cả ba. Icon trên thanh menu là bề mặt duy nhất luôn tồn
tại; cửa sổ Cài đặt là khung nhìn phụ, mở hay đóng không ảnh hưởng gì tới việc
app có đang giữ máy thức hay không.

Cái giá phải trả: app ở chế độ phụ trợ không sở hữu thanh menu hệ thống, nên ⌘W
không tự có. Nó được gắn lại bằng một nút ẩn (`CloseWindowShortcut`) — nói rõ ra
là một khoản nợ nhỏ, đổi lấy việc xoá ba cơ chế ở trên.

## Vì sao mỗi thứ có một nhịp riêng

Ứng dụng này tồn tại để quản lý năng lượng, nên đốt CPU cho hoạt ảnh là tự mâu
thuẫn. Ba nhịp, mỗi cái chỉ chạy khi cần:

| Thành phần | Nhịp | Chạy khi | Ai đánh nhịp |
|---|---|---|---|
| Ly cà phê (khói + mực) | 20 fps | đang hoạt động **và** panel đang mở | `TimelineView` |
| Số đếm ngược | 1 Hz | có hẹn giờ **và** panel đang mở | `TimelineView` |
| Nhãn menu bar | 1 Hz | **chỉ khi có hẹn giờ** | `CaffeineController.now` |
| Nhãn trợ năng | không có nhịp | — | — |

Điểm quan trọng: trước đây ly cà phê chạy 24 fps trong một cửa sổ chính **luôn
mở**, và số đếm ngược nằm chung khối đó. Nay cả hai chỉ tồn tại khi panel đang
hiển thị, còn khi panel đóng thì SwiftUI không kết xuất chúng nữa — nghĩa là ở
trạng thái thường trực, app không vẽ gì cả.

Nhãn menu bar là ngoại lệ, và nó không dùng `TimelineView`. Đây là một kết luận
từ **đo đạc chứ không phải suy đoán**: một nhãn `MenuBarExtra` dựng bằng
`TimelineView(.periodic(by: 1))` chỉ được vẽ lại **2 lần trong 8 giây** đang đếm
ngược, và cả hai lần đều do trạng thái đổi. SwiftUI kết xuất nhãn ấy vào một
`NSStatusItem`, và trong khung đó `TimelineView` không chạy. Hậu quả nếu để
nguyên: icon đứng im ở mức đầy suốt lần hẹn giờ — mất đúng thứ khiến nó đáng có
mặt trên thanh menu.

Cách đáng tin duy nhất là cho nhãn đọc một thuộc tính `@Observable` thật sự thay
đổi. Vì vậy `CaffeineController` giữ một `now` và một `Task` nhịp 1 Hz — nhưng
`Task` đó **chỉ sống khi `timerEndsAt != nil`**, và phần tính toán vẫn thuần
tuý: `iconState(at: Date)` nhận thời điểm từ ngoài nên test được mà không cần
chờ đồng hồ thật.

Nhãn menu bar còn được bảo vệ thêm bằng lượng tử hoá: `MenuBarIconState` làm
tròn tiến trình về 32 bậc. Lòng ly cao 8.8pt, ở màn hình 2x là 18 pixel — mọi
thay đổi nhỏ hơn 1/32 rơi vào cùng một pixel. Nhờ đó trạng thái trở thành khoá
cache dùng được, và một lần hẹn giờ 8 tiếng dựng 32 tấm ảnh thay vì 28.800.

## Vì sao nhãn trợ năng nói mốc kết thúc

`CoffeeGauge` từng đặt cả khối trong một `TimelineView` 24 fps, nên phần tử trợ
năng bọc ngoài bị dựng lại mỗi khung hình. Hai hậu quả:

- VoiceOver mất chỗ bám và đọc lại nhãn không ngừng;
- một truy vấn XCUITest lên cây đó chạy tới lúc hết giờ chờ mà không xong.

Nay nhãn nói **"Đang bật, hẹn giờ tới 15:47"** thay vì **"Đang bật, còn 14
phút"**. Nó chính xác hơn khi đọc thành lời, và đứng yên suốt lần hẹn giờ.

## Vì sao cài đặt được giải mã khoan dung

Cài đặt là dữ liệu của người dùng và sống lâu hơn mọi phiên bản app. `Codable`
sinh tự động ném lỗi khi thiếu một khoá, và `UserDefaultsSettingsStore` bắt lỗi
đó bằng cách trả về `Settings()` — tức là **xoá sạch cấu hình** chỉ vì bản app
cũ chưa ghi một trường mới.

Nay mỗi trường được đọc độc lập bằng `decodeIfPresent`, kèm `normalize()` kẹp
giá trị về khoảng hợp lệ (kể cả khi chúng tới từ một file plist sửa tay). Trường
`schemaVersion` được ghi ra để sau này còn chỗ bám khi cần migrate thật — tức là
khi *ý nghĩa* của một trường đã có thay đổi, chứ không phải khi thêm trường mới.

## Vì sao "Tắt" không tự bật lại

Đây là chỗ tinh tế nhất của app, và đã có người "sửa" nó thành lỗi.

`.stopAll` xoá `manual`, `timerEndsAt` và **mọi lý do trigger trong `state`** —
nhưng *không* đụng tới trạng thái nội bộ của từng trigger. `PowerSourceTrigger`
vẫn giữ `isCharging == true` nếu máy vẫn đang cắm sạc, và nó chỉ phát
`.triggerFired` trên một chuyển tiếp `false → true` thật sự.

Nếu reset baseline lúc `stopAll`, thông báo nguồn điện kế tiếp (mà điều kiện
chưa hề đổi) sẽ bật lại luật ngay lập tức — nút Tắt mất hết ý nghĩa.

Có một trường hợp biên đã được chấp nhận và cố ý không sửa: nếu người dùng đổi
một setting bất kỳ, `rebuildTriggers()` chạy lại, bộ trigger mới tự `refresh()`
và có thể bật lại luật đó ngay. Đó là hệ quả hợp lý của "đánh giá lại từ đầu",
và thêm state để chặn nó sẽ đắt hơn giá trị thu được.

## Kiểm thử

| Tầng | Công cụ | Phủ gì |
|---|---|---|
| Lõi | `swift test` (69 test) | reduce, assertion, trigger, lược đồ cài đặt, hẹn giờ, vẽ icon |
| IOKit thật | `IOKitBackingTests` | tạo assertion thật rồi đọc lại bằng `pmset -g assertions` |
| Giao diện | `CaffeinateUITests` (9 test) | nút → controller → state qua `UITestHarnessWindow`; chuyển ngữ ở cả ba lớp; nhãn trợ năng của mọi control trong cửa sổ Cài đặt |

Smoke test giao diện cố ý ít: XCUITest không chịu được nhịp chạy nền 1 Hz của
chế độ đếm ngược, và bẻ cong ứng dụng cho vừa công cụ là cái giá không đáng trả.
Phần đếm ngược được phủ tất định ở tầng lõi.

Cả hai smoke test đều chốt ngôn ngữ bằng `-AppleLanguages`. Không chốt thì kết
quả phụ thuộc vào cài đặt của máy đang chạy — và đó không phải giả thuyết: bộ
test này đã đỏ đúng một lần vì máy phát triển đặt `en-VN`, nên app hiện ra tiếng
Anh trong khi test khẳng định theo nhãn tiếng Việt.
