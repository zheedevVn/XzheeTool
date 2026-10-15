//
//  RequestGrouper.swift
//  XKit
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

public struct ErrorList<E: Error>: LocalizedError {

    public let errors: [E]
    public init(_ errors: [E]) {
        self.errors = errors
    }

    public var errorDescription: String? {
        errors.map { $0.localizedDescription }.localizedJoined()
    }

}
