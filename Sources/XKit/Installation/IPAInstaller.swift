//
//  IPAInstaller.swift
//  XKit
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation
import SwiftyMobileDevice

public final class IPAInstaller: Sendable {

    private let client: InstallationProxyClient
    public init(connection: Connection) async throws {
        self.client = try await connection.startClient()
    }

    public func install(
        uploaded: IPAUploader.UploadedIPA,
        progress: @escaping @Sendable (InstallationProxyClient.RequestProgress) -> Void
    ) async throws {
        try await client.install(
            package: uploaded.location,
            progress: progress
        )
    }

}
