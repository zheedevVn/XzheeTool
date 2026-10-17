# ZheeOffsetDump — Dylib dump offset: framework (ObjC) + metadata (il2cpp)

Inject vào app mục tiêu → tự động quét, ghi offset ra file.
Không hook, không sửa gì trong app — chỉ đọc runtime.

## Output

`<App Documents>/ZheeOffsets.txt`:

- **Header**: bundle ID, executable, danh sách **toàn bộ image đã load**
  (binary chính + từng framework) kèm base + size.
- **ObjC theo từng image**: class/method của từng framework,
  `offset = IMP - base` của image chứa nó (không phụ thuộc ASLR).
- **il2cpp (app Unity)**: gọi trực tiếp il2cpp API lúc runtime
  (cách mà Frida il2cpp-bridge dùng) — assembly → class → method
  (tên, signature, `methodPointer`, offset) + field (tên, type, field offset).
- **Metadata**: đường dẫn + size + header của `global-metadata.dat`
  (sanity, version, số lượng string) — file này + binary UnityFramework
  là đầu vào cho Il2CppDumper.

## Cách dùng

1. Inject `ZheeOffsetDump.dylib` vào IPA mục tiêu, cài vào máy.
2. Mở app, đợi vài giây (dump chạy nền; nếu il2cpp chưa khởi tạo, tự thử lại).
3. Lấy file `ZheeOffsets.txt` trong Documents của app.
4. Xem log (Console): `[ZheeOffsetDump] wrote ...`.

## Dùng với Frida / Il2CppDumper

- **Il2CppDumper** (máy tính): lấy binary `UnityFramework` + file
  `global-metadata.dat` (đường dẫn trong output) → chạy Il2CppDumper
  → `dump.cs` đầy đủ. RVA trong dump.cs + base trong output = địa chỉ
  lúc chạy (`VA = RVA + base`).
- **Frida** (máy tính): `frida -U -f <bundle> -l script.js` — dùng
  `Module.getBaseAddress()` + offset trong output để hook/đọc.

## Build (GitHub Action)

Workflow `.github/workflows/build-offsetdump.yml` build bằng `xcrun` trên
runner macOS, upload `ZheeOffsetDump.dylib` làm artifact.

## Chống phát hiện (anti-cheat / anti-dump)

Dylib cố tình né các dấu vết mà hệ thống chống tool hay quét:

- **Không dùng Frida**: native hoàn toàn — không có Frida Gadget/server,
  không mở port 27042, không có chuỗi "frida" trong bộ nhớ.
- **Không hook / không swizzle** method nào của app — anti-cheat kiểm tra
  IMP bị hook sẽ không thấy gì đổi.
- **Không gọi API debugger** (`ptrace`, `task_for_pid`, sysctl debug) —
  không chạm vào anti-debug.
- **Delay ngẫu nhiên 3–8s** trước khi hiện panel/chạy dump — không có
  timing cố định để fingerprint.
- **Nút "Xóa file"** trong panel: copy file xong bấm xóa để dọn dấu vết
  (anti-cheat hay quét Documents tìm `dump.cs`).

**Giới hạn nói thẳng**: nếu app quét danh sách image đã load (dyld) tìm
dylib lạ, hoặc tự kiểm tra chữ ký binary của chính nó, thì **bất kỳ dylib
inject nào cũng bị phát hiện** — không có dumper nào giấu được hoàn toàn.
Cách dùng an toàn: chỉ inject để dump 1 lần, copy file ra, bấm "Xóa file",
rồi cài lại bản app sạch (không inject) để chơi/bình thường.

## Ghi chú

- Không dump symbol C — chỉ ObjC runtime + il2cpp (class/method/field).
- `methodPointer` đọc từ field đầu tiên của `MethodInfo` (ổn định qua các
  bản il2cpp).
- Cần iOS 14+.
