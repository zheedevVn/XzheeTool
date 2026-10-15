//
//  App.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import ExampleDynamicLibrary
import ExampleSupport
import SwiftUI

@main struct DemoApp: ExampleApp {
    init() {
        let message = exampleDynamicLibraryFunction()
        guard message == "Hello from the dynamic library\n" else {
            fatalError("Unexpected message from dynamic library: \(message)")
        }
    }
}
