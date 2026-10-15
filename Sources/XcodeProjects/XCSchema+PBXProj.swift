//
//  XCSchema+PBXProj.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation
private import XcodeProj

extension XCSchema.Project {
    public func pbxprojRepresentation(name: String) throws -> Data {
        let xcprojData = try self.jsonRepresentation()
        let pbxproj = try PBXProj(xcprojData: xcprojData, projectName: name)
        // dataRepresentation should never return nil
        return try pbxproj.dataRepresentation() ?? Data()
    }

    public init(pbxprojRepresentation data: Data) throws {
        let pbxproj = try PBXProj(data: data)
        let xcprojData = try pbxproj.xcprojData()
        try self.init(jsonRepresentation: xcprojData)
    }
}
