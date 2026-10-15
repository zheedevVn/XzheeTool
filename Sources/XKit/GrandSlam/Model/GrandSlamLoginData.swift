//
//  GrandSlamLoginData.swift
//  XKit
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

struct GrandSlamLoginData: Decodable {
    let adsid: String
    let idmsToken: String
    let sk: Data
    let cookie: Data

    var identityToken: String {
        Data("\(adsid):\(idmsToken)".utf8).base64EncodedString()
    }

    private enum CodingKeys: String, CodingKey {
        case adsid
        case idmsToken = "GsIdmsToken"
        case sk
        case cookie = "c"
    }
}
