# ZheeTwitterDL — Dylib tải video X (Twitter) về Thư viện Ảnh

Nút nổi + panel tải video Tweet qua endpoint `api-zhee.vercel.app`.

## Tính năng

- **Nút nổi** tròn gradient, kéo thả mọi vị trí — bấm để mở/đóng panel.
- **Panel kính mờ** (dark glass): ô nhập link + **icon paste** (lấy link từ clipboard),
  nút **Tải video**, **thanh tiến trình + % to rõ**, dòng trạng thái.
- **Hỏi 1 lần thôi**: key Zhee chỉ hỏi 1 lần đầu, lưu Keychain, lần sau tự dùng
  (có nút “Đổi Zhee key” nếu muốn đổi). Quyền Ảnh iOS cũng chỉ hỏi 1 lần
  (quyền Add-Only — chỉ thêm ảnh, không đọc thư viện).
- Tải video bằng `NSURLSession` (hiện % thật), lưu vào Ảnh bằng `PHPhotoLibrary`.

## Cách dùng

1. Inject `ZheeTwitterDL.dylib` vào app X (Twitter) khi sideload
   (thêm `LC_LOAD_DYLIB`, ký lại IPA — dùng XzheeTool hoặc công cụ inject).
2. Mở app X → nút nổi tròn xuất hiện ở mép phải.
3. Bấm nút nổi → panel hiện → dán link Tweet (bấm icon paste) → bấm **Tải video**.
4. Lần đầu: nhập Zhee key (key của tài khoản api-zhee — lấy trong Hồ sơ
   trên `api-zhee.vercel.app`) → bấm ✓ → lưu, không hỏi lại nữa.
5. Xem % chạy → “Đã lưu vào Ảnh ✓”.

## Endpoint

```
GET https://api-zhee.vercel.app/api/mxh/twitter?<link Tweet đã encode>
Authorization: Bearer <Zhee key>
```

Dylib tự tìm link `.mp4` trong JSON trả về (không phụ thuộc tên field),
ưu tiên `video.twimg.com`. Nếu server đổi sang dạng `?url=…`, dylib tự
thử lại dạng đó.

## Build (GitHub Action)

Workflow `.github/workflows/build-dylib.yml` build bằng `xcrun` trên runner
macOS, upload `ZheeTwitterDL.dylib` làm artifact. Chạy khi push vào
`Tweaks/ZheeTwitterDL/**` hoặc bấm **Run workflow** tay.

## Vì sao Objective-C, không phải Swift?

Dylib inject vào app khác không mang theo Swift runtime — Objective-C chỉ
link framework hệ thống (UIKit / Photos / Security) nên load được ngay,
không cần nhúng runtime.

## Ghi chú

- Dylib **không hook** method nào của app X — chỉ thêm UI riêng, nên ít
  rủi ro crash khi X cập nhật.
- Cửa sổ nổi là pass-through: chạm ngoài nút/panel vẫn xuống app X bình thường.
- Cần iOS 14+.
