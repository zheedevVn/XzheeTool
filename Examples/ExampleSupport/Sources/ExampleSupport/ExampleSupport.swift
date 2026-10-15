//
//  ExampleSupport.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

public enum Example {}
extension Example {
    public static func pass() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            print("xtool test succeeded")
            exit(0)
        }
    }
}
