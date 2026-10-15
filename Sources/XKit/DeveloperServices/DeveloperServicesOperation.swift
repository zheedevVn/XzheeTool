//
//  DeveloperServicesOperation.swift
//  XKit
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

public protocol DeveloperServicesOperation: Sendable {
    associatedtype Response

    var context: SigningContext { get }

    func perform() async throws -> Response
}
