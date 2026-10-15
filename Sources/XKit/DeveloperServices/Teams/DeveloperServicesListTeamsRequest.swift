//
//  DeveloperServicesListTeamsRequest.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

public struct DeveloperServicesListTeamsRequest: DeveloperServicesRequest {

    public struct Response: Decodable, Sendable {
        public let teams: [DeveloperServicesTeam]
    }
    public typealias Value = [DeveloperServicesTeam]

    public var action: String { return "listTeams" }
    public var parameters: [String: Any] { return [:] }

    public func parse(_ response: Response) -> [DeveloperServicesTeam] {
        response.teams
    }

    public init() {}

}
