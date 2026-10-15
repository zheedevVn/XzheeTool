//
//  ExampleDynamicLibrary.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

public func exampleDynamicLibraryFunction() -> String {
    guard let bundled = #bundle.url(forResource: "response", withExtension: "txt")
        else { fatalError("Missing bundled.txt resource") }
    // swiftlint:disable:next force_try
    let contents = try! String(contentsOf: bundled, encoding: .utf8)
    return "Hello \(contents)"
}
