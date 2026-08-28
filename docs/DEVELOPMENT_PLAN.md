# Kế hoạch phát triển Smart Movie sau 3.0

> Cập nhật: 28/08/2026 · Chủ sở hữu: hai repo **Smart Movie iOS** và **Smart Movie Android**

Tài liệu này là roadmap duy nhất cho toàn bộ Smart Movie. Mỗi hạng mục được triển khai theo một lát cắt hoàn chỉnh trên Worker, Apple, Android, TV, companion và KMP khi nền tảng đó có liên quan. UI vẫn tuân theo chuẩn từng hệ điều hành; hợp đồng dữ liệu, hành vi lỗi, quyền riêng tư, localization và semantic version phải đồng bộ.

P0 kế thừa phạm vi phát hành đã thống nhất. **P1–P4 là đề xuất để duyệt và triển khai dần**, chưa phải cam kết version/ngày phát hành hay chức năng đã có. Chốt phạm vi và tiêu chí nghiệm thu từng tính năng trước khi viết code.

## Trạng thái hiện tại

- Source release train đang ở `3.0.0`; hợp đồng catalog/account chuẩn là `2.0.0`.
- `/v1` tiếp tục phục vụ client 2.0; `/v2` chỉ thay đổi theo hướng bổ sung và tương thích ngược.
- Catalog sâu, Search đa thực thể, Discover nâng cao, vùng/provider, PIN 18+, TMDb browser/TV auth, thư viện local-first, rating, đề xuất tài khoản và custom list đã có trong source.
- Việc còn lại của 3.0 chủ yếu là hạ tầng và phát hành: D1/secrets/callback domain, protected staging smoke, signing, CloudKit production, store metadata và QA thiết bị.
- Smart Movie không phát phim, không tạo tài khoản riêng, không nhận mật khẩu TMDb, không chứa TMDb credential trong client, không analytics và không quảng cáo.

## Thứ tự ưu tiên

### P0 — Hoàn tất và phát hành 3.0.0

Mục tiêu: biến source candidate hiện tại thành bản phát hành có thể rollback an toàn.

- Áp dụng D1 migrations cho staging/production; cấu hình khóa mã hóa session, TMDb token, callback origin và allowlist return URI.
- Kích hoạt DNS/TLS cho Worker staging và production; chạy catalog smoke, protected account smoke và kiểm tra cache/rate-limit/error envelope.
- Ưu tiên sửa luồng ảnh thật: xác nhận cấu hình TMDb, poster/backdrop/profile/logo và response ảnh trên mỗi client. Ngày 28/08/2026 hai domain Worker chưa phân giải DNS trên máy kiểm tra; ảnh preview cục bộ không thay thế smoke production. Xem [chẩn đoán và kiểm thử ảnh](IMAGE_LOADING.md).
- Hoàn thiện QA compact Detail: tránh rút gọn nhãn hành động Favorite/Watchlist ở bề ngang nhỏ và kiểm tra sáu locale/Dynamic Type. Bổ sung capture riêng Catalyst, visionOS, native desktop/JS và thiết bị Android/TV/Wear; không coi ảnh Web hoặc component golden là ảnh các nền tảng này.
- Hoàn tất Apple signing, CloudKit production schema, App Store Connect metadata, privacy/support URL và ảnh store.
- Hoàn tất Android signing, Play Internal Testing cho phone/tablet/TV/Wear, age rating, data safety và ảnh store.
- Build candidate cho native macOS, Catalyst, visionOS, desktop JVM, JS và Wasm; xác nhận không có secret/session trong binary, log hoặc fixture.
- Chỉ promote Worker production sau khi checksum contract trên Android `main` khớp repo chuẩn và toàn bộ client candidate xanh.

**Điều kiện hoàn thành:** hai app mang cùng version `3.0.0`, contract checksum khớp, smoke test production pass, store candidate đã QA và rollback đã diễn tập.

### P1 — Smart Movie 3.1: Theo dõi tập phim và lịch phát hành

Mục tiêu: giúp người dùng biết mình đang xem tới đâu và nội dung nào sắp phát hành mà không biến Smart Movie thành dịch vụ streaming.

- Đánh dấu đã xem cho season/episode; hiển thị tiến độ series, tập kế tiếp và nút tiếp tục từ Library/Detail.
- Lưu tiến độ local-first, đọc offline và có migration không mất Favorite/Watchlist hiện tại.
- Thêm lịch phát hành theo region/timezone cho movie, season và episode; lọc theo ngày/tuần/tháng.
- Thêm nhắc lịch tùy chọn trên iOS/Android/desktop. Notification không chứa nội dung 18+ và không xuất hiện trên Watch/Wear nếu chưa đủ ngữ cảnh an toàn.
- Watch/Wear chỉ hiển thị tập kế tiếp an toàn và handoff về đúng series/season/episode trên điện thoại.

**Không làm trong 3.1:** đồng bộ tiến độ lên server riêng hoặc phát video.

### P2 — Smart Movie 3.2: Thư viện và Discovery mạnh hơn

Mục tiêu: giúp catalog lớn vẫn dễ tìm lại và dễ quản lý.

- Lưu bộ lọc Discover, region/provider preset và truy vấn Search gần đây trên từng thiết bị.
- Bổ sung sort/filter cho Favorite, Watchlist, rating và custom list theo loại, năm, điểm, ngày thêm và availability.
- Cho phép chọn nhiều mục để chuyển Favorite/Watchlist, gỡ local hoặc thêm vào TMDb list; tất cả mutation tiếp tục đi qua outbox bền vững.
- Thêm tag/ghi chú cục bộ tùy chọn; không gửi nội dung này tới TMDb hoặc Worker.
- Bổ sung trạng thái cache/offline rõ ràng và công cụ xóa cache không làm mất thư viện.

### P3 — Smart Movie 3.3: Tích hợp hệ điều hành và companion

Mục tiêu: đưa Smart Movie tới đúng nơi người dùng đang tìm nội dung mà vẫn giữ dữ liệu tối thiểu.

- Apple: WidgetKit, Spotlight và App Intents cho Favorite/Watchlist/tập kế tiếp an toàn.
- Android: home-screen widget, launcher shortcut và App Search cho dữ liệu local được người dùng cho phép.
- TV: cải thiện deep link, focus restoration, remote search và QR auth timeout/recovery.
- Desktop/Web: keyboard command palette, deep-link routing, PWA install/update flow và khôi phục phiên làm việc.
- Watch/Wear: trạng thái kết nối, retry/handoff rõ ràng hơn; vẫn không đăng nhập độc lập và không hiển thị nội dung 18+.

### P4 — Smart Movie 3.4: Chất lượng, hiệu năng và mở rộng ngôn ngữ

Mục tiêu: tối ưu trải nghiệm trước khi mở rộng thêm bề mặt sản phẩm.

- Đặt ngân sách image prefetch/cache theo thiết bị, giảm thời gian mở Home/Detail và bộ nhớ đỉnh.
- Hoàn thiện Dynamic Type/font scaling, VoiceOver/TalkBack, keyboard, D-pad, Reduce Motion, contrast và RTL.
- Mở rộng locale dựa trên nhu cầu thực tế; locale mới phải có fixture, screenshot và kiểm tra fallback.
- Thêm performance benchmark, startup regression gate và network trace đã loại dữ liệu nhạy cảm.
- Rà soát privacy disclosure, TMDb/JustWatch attribution và store policy ở mỗi release train.

## Quy trình cho từng tính năng

1. Cập nhật parity spec và ghi rõ nền tảng áp dụng/ngoại lệ.
2. Nếu cần dữ liệu mới, cập nhật Worker + OpenAPI + fixture trước; thay đổi `/v2` phải additive.
3. Mở thay đổi Apple và Android/KMP theo cùng milestone; domain model vẫn native từng repo.
4. Hoàn thiện trạng thái loading/empty/error/offline, retry/cancellation, 6 locale, accessibility và privacy.
5. Thêm unit/contract/UI test cùng screenshot phù hợp cho phone, tablet, TV, companion và desktop/web.
6. Cập nhật README, About, release manifest và tài liệu liên quan.
7. Commit và push ngay sau khi lát cắt tính năng đã pass kiểm tra của repo đó; không gom nhiều tính năng chưa hoàn chỉnh vào một commit phát hành.

## Definition of Done

Một tính năng chỉ được đánh dấu hoàn thành khi:

- Hành vi và dữ liệu nhất quán trên các client thuộc phạm vi; khác biệt UI nền tảng đã được ghi rõ.
- Không làm hỏng `/v1`, fixture cũ hoặc dữ liệu local sau migration.
- Test tự động liên quan pass; screenshot/golden và 6 locale đã cập nhật.
- Không có credential, opaque session, PIN, dữ liệu cá nhân hoặc nội dung 18+ trong log, fixture, preview hay metadata công khai.
- README/About phản ánh đúng tính năng; commit đã được push và liên kết với milestone chung.

## Ngoài phạm vi dài hạn

- Phát hoặc lưu trữ phim/tập phim ngoài trailer và liên kết availability do TMDb cung cấp.
- Smart Movie account riêng, thu username/password TMDb, guest session, analytics hoặc quảng cáo.
- Đồng bộ PIN 18+, tag/ghi chú riêng tư hoặc dữ liệu companion lên Worker.
- Đưa credential TMDb/Cloudflare vào bất kỳ client, fixture, screenshot hoặc repository nào.
