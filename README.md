# XzheeTool

<div align="center">

**Công cụ đa nền tảng thay thế Xcode — Xây dựng, ký số và triển khai ứng dụng iOS trực tiếp trên Linux, Windows (WSL) và macOS.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)
[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-F05138.svg?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows%20(WSL)-555555.svg)]()
[![Author](https://img.shields.io/badge/Author-H%E1%BB%93%20%C4%90%E1%BB%A9c%20Minh%20(zheedevVn)-success.svg)](https://github.com/zheedevVn)

---

**[ 🇺🇸 English ](#-english)** &nbsp;|&nbsp; **[ 🇻🇳 Tiếng Việt ](#-tiếng-việt)**

---

</div>

---

<a name="english"></a>
## 🇺🇸 English

### Overview

**XzheeTool** is an open-standard, cross-platform CLI tool and library designed to replace Xcode's build, provisioning, signing, and device deployment workflows without requiring a Mac machine.

- ✓ **Zero Xcode dependency**: Build SwiftPM packages into full-fledged iOS `.ipa` applications on Linux and Windows.
- ✓ **Integrated Provisioning & Signing**: Automatic certificate management, mobile provisioning profile handling, and app signing.
- ✓ **Direct Device Communication**: Deploy, install, launch, debug, and manage iOS devices over USB via native protocol implementations.
- ✓ **Apple Developer Services API**: Programmatic authentication and control over App Store Connect and Developer portal resources.

---

### Command Line Interface

```bash
$ xzheetool --help
OVERVIEW: Cross-platform iOS development and deployment toolkit.

USAGE: xzheetool <subcommand>

CONFIGURATION SUBCOMMANDS:
  setup                   Set up toolchain and dependencies for iOS development
  auth                    Manage Apple Developer Services authentication
  sdk                     Manage the Darwin Swift SDK

DEVELOPMENT SUBCOMMANDS:
  new                     Create a new XzheeTool SwiftPM iOS project
  dev                     Build, sign, install, and run an iOS project in real time
  ds                      Interact with Apple Developer Services

DEVICE SUBCOMMANDS:
  devices                 List connected iOS devices
  install                 Install an .ipa file to a target device
  uninstall               Uninstall an app from a device
  launch                  Launch an installed application on device
```

#### Workflow Demonstration

```text
$ xzheetool dev
Planning build...
Compiling Swift sources...
[8/8] Linking HelloApp
Build complete in 4.2s!

Detecting connected device...
Found target: iPhone (UDID: 00008110-001234567890ABCD)

[1/6] Preparing device environment    [✓] 100%
[2/6] Fetching provisioning profile  [✓] 100%
[3/6] Signing application bundle      [✓] 100%
[4/6] Packaging .ipa                  [✓] 100%
[5/6] Transferring and installing     [✓] 100%
[6/6] Launching application           [✓] 100%

App is now running on your device!
```

---

### Library Usage

You can also integrate **XKit** as a SwiftPM dependency into your own Swift tools or services:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/zheedevVn/XzheeTool.git", branch: "main")
],
targets: [
    .target(
        name: "MyTool",
        dependencies: [
            .product(name: "XKit", package: "XzheeTool")
        ]
    )
]
```

---

<a name="tiếng-việt"></a>
## 🇻🇳 Tiếng Việt

### Tổng quan

**XzheeTool** là giải pháp mã nguồn mở đa nền tảng thay thế hoàn toàn Xcode trong các công việc biên dịch (build), ký số (code signing), cấp chứng chỉ (provisioning) và nạp ứng dụng iOS trực tiếp lên thiết bị thật mà không bắt buộc phải có máy tính Mac.

- ✓ **Không phụ thuộc Xcode**: Biên dịch dự án SwiftPM thành file `.ipa` hoàn chỉnh trực tiếp trên Linux hoặc Windows (WSL).
- ✓ **Tự động ký số & chứng chỉ**: Tự động quản lý Apple Certificates, Mobileprovisioning và nhúng quyền hạn (Entitlements).
- ✓ **Giao tiếp thiết bị qua USB**: Kết nối, cài đặt, khởi chạy và quản lý ứng dụng trên iPhone/iPad thông qua giao thức `usbmuxd`.
- ✓ **Tích hợp Apple Developer API**: Đăng nhập và tương tác trực tiếp với cổng Apple Developer Portal và App Store Connect.

---

### Yêu cầu hệ thống & Cài đặt

1. **Linux / Windows (WSL)**:
   - Cài đặt công cụ Swift 6.0+ từ [swift.org](https://swift.org/install/linux).
   - Cài đặt dịch vụ USB: `sudo apt-get install usbmuxd libimobiledevice6`.
   - Đối với Windows: Sử dụng WSL2 kết hợp với `usbipd-win` để chuyển tiếp cổng USB thiết bị vào WSL.
2. **macOS**:
   - Yêu cầu macOS 14.0 trở lên và Swift 6.0+.

---

### Hướng dẫn câu lệnh CLI

```bash
# Khởi tạo dự án iOS mới
$ xzheetool new --name MyApp

# Đăng nhập tài khoản Apple Developer
$ xzheetool auth login

# Tải và cấu hình Darwin Swift SDK
$ xzheetool sdk install

# Biên dịch, ký số và chạy thẳng lên iPhone đang cắm USB
$ xzheetool dev

# Cài đặt file .ipa có sẵn
$ xzheetool install app.ipa
```

---

### Tích hợp thư viện vào dự án Swift

Sử dụng thư viện **XKit** trong dự án riêng của bạn thông qua Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/zheedevVn/XzheeTool.git", branch: "main")
],
targets: [
    .target(
        name: "UngDungCuaToi",
        dependencies: [
            .product(name: "XKit", package: "XzheeTool")
        ]
    )
]
```

---

## 👨‍💻 Tác giả & Bản quyền / Author & License

- **Tác giả / Author**: **Hồ Đức Minh (zheedevVn)**
- **GitHub**: [@zheedevVn](https://github.com/zheedevVn)
- **Repository**: [https://github.com/zheedevVn/XzheeTool](https://github.com/zheedevVn/XzheeTool)
- **Email**: [minhbach251207@gmail.com](mailto:minhbach251207@gmail.com)
- **Giấy phép / License**: Phát hành theo giấy phép [MIT License](LICENSE.md). Toàn quyền sử dụng, sửa đổi và phân phối.
