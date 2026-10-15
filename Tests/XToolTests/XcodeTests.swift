//
//  XcodeTests.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Testing
import Foundation

@Test(.requiresXcode) func validateXcode() {
    let xcode = TestXcode.current()
    let swift = xcode.appending(path: "Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")
    #expect(
        FileManager.default.fileExists(atPath: swift.path),
        "Invalid or unrecognized layout for Xcode.app at \(xcode.path)"
    )
}
