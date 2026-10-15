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
    name: "DemoSimple",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "DemoSimple",
            targets: ["DemoSimple"]
        ),
    ],
    dependencies: [
        .package(path: "../ExampleSupport"),
    ],
    targets: [
        .target(
            name: "DemoSimple",
            dependencies: [
                "ExampleSupport",
            ]
        ),
    ]
)
