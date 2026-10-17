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

## Ghi chú

- Không dump symbol C — chỉ ObjC runtime + il2cpp (class/method/field).
- `methodPointer` đọc từ field đầu tiên của `MethodInfo` (ổn định qua các
  bản il2cpp).
- Cần iOS 14+.
