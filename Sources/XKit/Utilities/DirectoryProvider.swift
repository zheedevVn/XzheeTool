//
//  DirectoryProvider.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation
import Dependencies

private struct PersistentDirectoryProvider: DependencyKey, Sendable {
    var directory: URL

    static let liveValue = PersistentDirectoryProvider(
        directory: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/xtool")
    )
}

extension DependencyValues {
    public var persistentDirectory: URL {
        get { self[PersistentDirectoryProvider.self].directory }
        set { self[PersistentDirectoryProvider.self].directory = newValue }
    }
}
