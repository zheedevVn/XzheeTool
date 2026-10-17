# ZheeOffsetDump v4 — Dylib dump offset: framework (ObjC) + metadata (il2cpp)

Inject vào app bất kỳ → tự động quét, ghi offset ra file.
Không hook, không sửa gì trong app — chỉ đọc runtime.
Chạy trên mọi app (không hardcode bundle ID).

## Panel

Nút nổi logo Z (kéo thả) → panel gần full màn hình, sidebar trái
(Dump | Cài đặt | About, nút đang chọn nền xanh) + nội dung bên phải,
mở app là tự chạy dump:

- **Dump**: toggle nhanh (Tự động Dump + Full offset) + log live có viền +
  thanh tiến trình + nút Dump lại (xanh) / Xóa file (đỏ) / Xuất ra Tải về (xanh lá).
- **Cài đặt**: toggle từng phần (Tự động Dump, ObjC, Symbols, il2cpp,
  Xuất file gốc, **Full offset**, switch xanh lá khi bật), chọn kích thước
  panel (Nhỏ / Vừa / Lớn). Cài đặt lưu tự động. Kéo góc dưới-phải panel
  để chỉnh kích thước tùy ý.
- **About**: logo, tác giả Hồ Đức Minh — Zhee Dev, info app (bundle ID,
  phiên bản, thiết bị, iOS), nút Telegram (xanh) + GitHub bấm được.

Panel tự dựng lại khi xoay ngang/dọc.

## Output

Trong Documents của app, sau khi dump xong:

- **`ZheeOffsets.txt`**: header (bundle ID, executable, toàn bộ image đã load
  kèm base + size) + ObjC theo từng image **trong app bundle** (`offset = IMP - base`,
  không phụ thuộc ASLR; bật **Full offset** trong Cài đặt để dump cả system framework)
  + Mach-O symbols (C/C++) + metadata header.
- **`dump.cs`**: il2cpp (app Unity) qua API lúc runtime — assembly → class →
  method (tên, signature, `methodPointer`, offset/RVA) + field (tên, type, field offset).
  Tương đương output của Il2CppDumper nhưng lấy từ runtime (đã giải mã).
  Cuối dump có dòng kiểm tra: mọi offset đều nằm trong image chứa nó.
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

## Bảo vệ dylib (chống dịch ngược)

Source được harden để dylib khó bị phân tích:

- **Chuỗi nhạy cảm mã hóa XOR**: tên API il2cpp, tên file output,
  đường dẫn metadata, key UserDefaults đều lưu dạng byte XOR, chỉ giải mã
  lúc chạy — `strings` không thấy.
- **Tên trung tính**: class ObjC + method + property + hàm C đều đổi sang
  tên ngắn vô nghĩa (`ZDC`, `rD`, `bP`…) — class-dump không lộ chức năng.
- **Chặn debugger**: nếu có debugger đính kèm (P_TRACED), dylib không chạy.
- **Strip symbol** (cần sửa workflow, xem dưới): bỏ bảng symbol local khỏi
  dylib — tên hàm C / biến static không còn trong binary.

Sửa bước Build trong `.github/workflows/build-offsetdump.yml` (trên github.com):

```yaml
xcrun -sdk iphoneos clang -arch arm64 -dynamiclib -fobjc-arc -Os \
  -isysroot "$SDK" -miphoneos-version-min=14.0 \
  -Wl,-x \
  -framework Foundation -framework UIKit \
  -framework CoreGraphics -framework QuartzCore \
  -o ZheeOffsetDump.dylib Tweaks/ZheeOffsetDump/ZheeOffsetDump.m
```

**Giới hạn nói thẳng**: obfuscation chỉ nâng rào cản — người quyết tâm với
Hopper/IDA + patch vẫn phân tích được. Không có cách nào chống tuyệt đối.

## Chống phát hiện (anti-cheat / anti-dump)

Dylib cố tình né các dấu vết mà hệ thống chống tool hay quét:

- **Không dùng Frida**: native hoàn toàn — không có Frida Gadget/server,
  không mở port 27042, không có chuỗi "frida" trong bộ nhớ.
- **Không hook / không swizzle** method nào của app — anti-cheat kiểm tra
  IMP bị hook sẽ không thấy gì đổi.
- **Không gọi API debugger** (`ptrace`, `task_for_pid`, sysctl debug) —
  không chạm vào anti-debug.
- **Delay ngẫu nhiên 1–2s** trước khi hiện panel/chạy dump — không có
  timing cố định để fingerprint.
- **Nút "Xóa file"** trong panel: copy file xong bấm xóa để dọn dấu vết
  (anti-cheat hay quét Documents tìm `dump.cs`).
- **Không crash khi gặp kiểm tra**: mọi bước dump đều kiểm tra biên /
  con trỏ NULL trước khi đọc; lỗi chỉ ghi log, không crash app host.

**Giới hạn nói thẳng**: nếu app quét danh sách image đã load (dyld) tìm
dylib lạ, hoặc tự kiểm tra chữ ký binary của chính nó, thì **bất kỳ dylib
inject nào cũng bị phát hiện** — không có dumper nào giấu được hoàn toàn.
Cách dùng an toàn: chỉ inject để dump 1 lần, copy file ra, bấm "Xóa file",
rồi cài lại bản app sạch (không inject) để chơi/bình thường.

## Ghi chú

- Dump cả symbol C (Mach-O symtab) + ObjC runtime + il2cpp (class/method/field).
- `methodPointer` đọc từ field đầu tiên của `MethodInfo` (ổn định qua các
  bản il2cpp).
- Offset = địa chỉ − base của image chứa nó (không phụ thuộc ASLR).
  Cuối mỗi lần dump, dylib tự kiểm tra: mọi offset đều nằm trong image —
  nếu có method nào rơi ngoài image sẽ ghi rõ số lượng vào log.
- Cần iOS 14+.
