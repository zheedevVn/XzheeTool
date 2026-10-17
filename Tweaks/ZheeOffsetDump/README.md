# ZheeOffsetDump — Dylib dump offset: framework (ObjC) + metadata (il2cpp)

Inject vào app mục tiêu → tự động quét, ghi offset ra file.
Không hook, không sửa gì trong app — chỉ đọc runtime.

## Output

Trong Documents của app, sau khi dump xong:

- **`ZheeOffsets.txt`**: header (bundle ID, executable, toàn bộ image đã load
  kèm base + size) + ObjC theo từng image **trong app bundle** (`offset = IMP - base`,
  không phụ thuộc ASLR; bỏ method của system framework cho nhẹ file) + Mach-O symbols (C/C++)
  của image trong app bundle + metadata header.
- **`dump.cs`**: il2cpp (app Unity) qua API lúc runtime — assembly → class →
  method (tên, signature, `methodPointer`, offset/RVA) + field (tên, type, field offset).
  Tương đương output của Il2CppDumper nhưng lấy từ runtime (đã giải mã).
- **`global-metadata.dat`**: copy nguyên file metadata của app — đầu vào cho Il2CppDumper.
- **`UnityFramework`**: copy nguyên binary UnityFramework — đầu vào cho Il2CppDumper.

## Cách dùng

1. Inject `ZheeOffsetDump.dylib` vào IPA mục tiêu, cài vào máy.
2. Mở app → panel "Zhee Dump" hiện ra, log chạy live. Đợi tới "HOÀN TẤT".
3. Lấy 4 file trong Documents của app (qua Filza / Files / iMazing…),
   hoặc bấm "Xuất ra Tải về" trong panel → chọn thư mục Tải về.
4. Muốn dọn dấu vết: bấm "Xóa file" trong panel.

## Dùng với Frida / Il2CppDumper

- **Il2CppDumper** (máy tính): lấy 2 file `UnityFramework` + `global-metadata.dat`
  trong Documents → chạy Il2CppDumper → `dump.cs` đầy đủ.
  RVA trong dump.cs + base trong output = địa chỉ lúc chạy (`VA = RVA + base`).
  Lưu ý: nếu game mã hóa `global-metadata.dat` trên đĩa, Il2CppDumper đọc file
  copy ra có thể fail — khi đó dùng `dump.cs` của dylib (lấy từ runtime, đã giải mã).
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
