//
//  UninstallCommand.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import Foundation
import XKit
import SwiftyMobileDevice
import ArgumentParser

struct UninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall an installed app"
    )

    @OptionGroup var connectionOptions: ConnectionOptions

    @Argument(
        help: "The app to uninstall"
    ) var bundleID: String

    func run() async throws {
        let client = try await connectionOptions.client()
        let installProxy = try InstallationProxyClient(device: client.device, label: "xtool-inst")
        do {
            try await installProxy.uninstall(
                bundleID: bundleID,
                progress: { _ in }
            )
        } catch {
            print("Failed: \(error)")
            return
        }
        print("Success!")
    }
}
