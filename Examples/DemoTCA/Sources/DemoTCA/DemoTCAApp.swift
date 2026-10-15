//
//  DemoTCAApp.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import SwiftUI
import ComposableArchitecture

@main
struct DemoTCAApp: App {
    private let store = Store(initialState: CounterFeature.State()) {
        CounterFeature()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
