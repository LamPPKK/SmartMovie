# Smart Movie Apple screen gallery

Bộ ảnh này ghi lại UI phát triển của release train 3.0, không phải bằng chứng đã phát hành hoặc tải ảnh TMDb production. Các bản catalog dùng preview `/v1` + `/v2` cục bộ; account trả về trạng thái chưa đăng nhập. Hình trừu tượng là ảnh demo được tạo ngày 28/08/2026, không phải poster phim hay ảnh diễn viên thật. Không xem việc tải được ảnh demo là trạng thái production đã đạt yêu cầu.

## iPhone

<table>
  <tr>
    <td width="33%" align="center"><strong>Home</strong><br><sub>Hero, Movie/TV switch và catalog shelves</sub></td>
    <td width="33%" align="center"><strong>Detail</strong><br><sub>Metadata, trailer và thư viện local-first</sub></td>
    <td width="33%" align="center"><strong>Profile</strong><br><sub>TMDb auth, region và PIN nội dung 18+</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/iphone-home.png" alt="Smart Movie iOS Home on iPhone" width="300"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/iphone-detail.png" alt="Smart Movie iOS title detail on iPhone" width="300"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/iphone-profile.png" alt="Smart Movie iOS Profile on iPhone" width="300"></td>
  </tr>
</table>

### Detail và Dynamic Type — 29/08/2026

Detail iPhone được chụp lại sau khi sửa nhóm nút và metadata adaptive. Ở cỡ chữ thường, Trailer/Favorite/Watchlist hiển thị đầy đủ. Ở `accessibility-extra-extra-extra-large`, điểm số/năm/thời lượng chuyển thành cột; Watchlist đọc được đầy đủ sau khi cuộn. Đây là kiểm tra iPhone 16/iOS 18.6, tiếng Anh, không phải nghiệm thu toàn bộ Dynamic Type, locale hay luồng tài khoản.

<details>
  <summary>Ảnh QA cỡ chữ Accessibility lớn nhất</summary>
  <table>
    <tr>
      <td><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/iphone-detail-accessibility-metadata.png" alt="iPhone Detail metadata at maximum Accessibility text size" width="300"></td>
      <td><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/iphone-detail-accessibility-watchlist.png" alt="iPhone Detail Watchlist label after scrolling at maximum Accessibility text size" width="300"></td>
    </tr>
  </table>
</details>

## iPad và Mac

<table>
  <tr>
    <td width="50%" align="center"><strong>iPad</strong><br><sub>Universal app với bố cục adaptive</sub></td>
    <td width="50%" align="center"><strong>Native macOS</strong><br><sub>NavigationSplitView, keyboard và cửa sổ resizable</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/ipad-home.png" alt="Smart Movie iOS adaptive Home on iPad" width="660"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/macos-home.png" alt="Smart Movie native macOS Home" width="660"></td>
  </tr>
</table>

Mac Catalyst dùng cùng universal SwiftUI composition với iPad ở cửa sổ mở rộng. visionOS dùng cùng `SmartMovieKit` trong cửa sổ resizable và thêm detail window; máy chụp hiện không có visionOS Simulator runtime nên tài liệu không gắn nhãn một ảnh nền tảng khác thành ảnh visionOS.

## Apple TV và Apple Watch

<table>
  <tr>
    <td width="72%" align="center"><strong>Apple TV</strong><br><sub>5 destination, focus và Siri Remote/D-pad</sub></td>
    <td width="28%" align="center"><strong>Apple Watch</strong><br><sub>Safe title/episode context và iPhone handoff</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/apple-tv-home.png" alt="Smart Movie Home on Apple TV" width="760"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/LamPPKK/Smart-Movie-iOS/main/docs/images/screenshots/watch-remote.png" alt="Smart Movie companion remote on Apple Watch" width="260"></td>
  </tr>
</table>

## Phạm vi ảnh

Home iPhone, Home iPad, native macOS và Apple TV được chụp ngày 28/08/2026 sau bản sửa `1806c44`; Profile iPhone thuộc lượt preview trước đó cùng ngày. Detail iPhone được cập nhật ngày 29/08/2026 với các nhãn hành động đầy đủ. Watch vẫn là baseline cũ. Mỗi ảnh chỉ chứng minh bề mặt đã chụp, không thay thế kiểm tra các nền tảng dùng chung source. QA chữ lớn vẫn còn các hàng thông tin phía dưới (ví dụ Status), luồng signed-in rating và kiểm tra VoiceOver/thiết bị thực.

| Bề mặt | Ảnh đại diện | Nguồn |
| --- | --- | --- |
| iPhone | Home, Detail, Profile | iOS 18.6 Simulator + local preview; Home/Detail xác minh sau sửa ảnh |
| iPad | Home adaptive | iPadOS 18.6 Simulator + universal app, 28/08/2026 |
| Mac Catalyst | Chưa có capture riêng | Không dùng ảnh iPad thay cho bằng chứng Catalyst |
| Native macOS | Home | `SmartMovieNativeMac` build chạy thật, 28/08/2026 |
| Apple TV | Home | tvOS 26.2 Simulator + `SmartMovieTV`, 28/08/2026 |
| Apple Watch | Remote | Baseline companion cũ, chưa chụp lại cùng lượt sửa ảnh |
| Apple Vision Pro | Chưa có capture riêng | Local visionOS runtime chưa cài; không suy ra chất lượng UI từ build |

Ảnh public không chứa account token, PIN, lịch sử tìm kiếm, custom list cá nhân hoặc nội dung 18+. Ảnh store cuối cùng phải được chụp lại trên runtime/thiết bị phát hành và tuân theo kích thước App Store Connect.

Xem [IMAGE_LOADING.md](IMAGE_LOADING.md) để phân biệt kiểm thử ảnh preview, lỗi bố cục sau khi ảnh tải xong và blocker DNS production.
