//
//  GrandSlamEndpoints.swift
//  XKit
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

struct GrandSlamEndpoints: Decodable {
    let gsService: String
    let secondaryAuth: String
    let trustedDeviceSecondaryAuth: String
    let validateCode: String
    let midStartProvisioning: String
    let midFinishProvisioning: String
}

enum GrandSlamEndpoint: Sendable {
    case lookup(KeyPath<GrandSlamEndpoints, String> & Sendable)
    case url(URL)
}
