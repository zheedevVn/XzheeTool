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
    name: "DemoDynamic",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "DemoDynamic",
            targets: ["DemoDynamic"]
        ),
    ],
    dependencies: [
        .package(path: "../ExampleSupport"),
    ],
    targets: [
        .target(
            name: "DemoDynamic",
            dependencies: [
                "ExampleSupport",
                .product(name: "ExampleDynamicLibrary", package: "ExampleSupport"),
            ]
        ),
    ]
)
