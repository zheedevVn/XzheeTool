// swift-tools-version: 6.0
//
//  Package.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//


import PackageDescription

let package = Package(
    name: "DemoTCA",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "DemoTCA",
            targets: ["DemoTCA"]
        ),
    ],
    dependencies: [
        .package(path: "../ExampleSupport"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "DemoTCA",
            dependencies: [
                "ExampleSupport",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
    ]
)
