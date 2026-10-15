//
//  DeveloperServicesAssignAppGroupRequest.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation

public final class DeveloperServicesAssignAppGroupRequest: DeveloperServicesPlatformRequest {

    public struct Response: Decodable, Sendable {}
    public typealias Value = Response

    public let platform: DeveloperServicesPlatform
    public let teamID: DeveloperServicesTeam.ID
    public let appIDID: String
    public let groupID: DeveloperServicesAppGroup.ID

    var subAction: String { return "assignApplicationGroupToAppId" }
    var subParameters: [String: Any] {
        return [
            "teamId": teamID.rawValue,
            "appIdId": appIDID,
            "applicationGroups": groupID.rawValue
        ]
    }

    public init(
        platform: DeveloperServicesPlatform,
        teamID: DeveloperServicesTeam.ID,
        appIDID: String,
        groupID: DeveloperServicesAppGroup.ID
    ) {
        self.platform = platform
        self.teamID = teamID
        self.appIDID = appIDID
        self.groupID = groupID
    }

}
