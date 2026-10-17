# ZheeOffsetDump — Dylib dump offset ObjC runtime

Inject vào app mục tiêu → tự động quét toàn bộ class ObjC, ghi offset ra file.
Không hook, không sửa gì trong app — chỉ đọc runtime.

## Output

`<App Documents>/ZheeOffsets.txt` (mở bằng Files / trình duyệt file của tool sideload):

- Header: bundle ID, executable, image base, ASLR slide, danh sách image đã load.
- Từng class (chỉ method có IMP nằm trong binary chính):
  ```
  [ClassName] -selector | type encoding | IMP=0x... | offset=0x...
  [ClassName] +selector | ... | offset=0x...
  [ClassName] ivar name (type) | offset=0x...
  ```
- `offset = IMP - imageBase` — ổn định qua các lần chạy, không phụ thuộc ASLR.
  Dùng offset này để hook bằng địa chỉ (vd `MSHookFunction` / offset hook).

## Cách dùng

1. Inject `ZheeOffsetDump.dylib` vào IPA mục tiêu, cài vào máy.
2. Mở app, đợi ~2 giây (dump chạy nền).
3. Lấy file `ZheeOffsets.txt` trong Documents của app.
4. Xem log (Console): `[ZheeOffsetDump] wrote ... (N classes, M methods, K ivars)`.

## Build (GitHub Action)

Workflow `.github/workflows/build-offsetdump.yml` build bằng `xcrun` trên
runner macOS, upload `ZheeOffsetDump.dylib` làm artifact.

## Ghi chú

- Chỉ dump method thuộc binary chính (bỏ qua method của UIKit/hệ thống).
- Không dump symbol C — chỉ ObjC runtime (class/method/ivar).
- Cần iOS 14+.
