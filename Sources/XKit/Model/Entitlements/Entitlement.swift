//
//  Entitlement.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation
import ProtoCodable

public protocol Entitlement: ProtoCodable, Sendable {
    static var identifier: String { get }
}
