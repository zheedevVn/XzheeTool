//
//  GrandSlamAuthCompleteRequest.swift
//  XKit
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

struct GrandSlamAuthCompleteRequest: GrandSlamOperationRequest {

    typealias Decoder = GrandSlamOperationDecoder<Value>
    struct Value: Decodable {
        let hamk: Data
        let encryptedResponse: Data
        let negProto: Data
        let sc: Data?

        private enum CodingKeys: String, CodingKey {
            case hamk = "M2"
            case encryptedResponse = "spd"
            case negProto = "np"
            case sc
        }
    }

    static let operation = "complete"

    let username: String
    let cookie: String
    let m1Data: Data

    var parameters: [String: Any] {
        [
            "c": cookie,
            "M1": m1Data,
        ]
    }

}
