import ProjectDescription

let project = Project(
    name: "SnapCompanion",
    options: .options(disableSynthesizedResourceAccessors: true),
    packages: [
        .local(path: "."),
        .remote(
            url: "https://github.com/onevcat/Kingfisher.git",
            requirement: .exact("8.11.0")
        ),
        .remote(
            url: "https://github.com/apple/swift-nio.git",
            requirement: .upToNextMajor(from: "2.65.0")
        ),
        .remote(
            url: "https://github.com/apple/swift-nio-ssl.git",
            requirement: .upToNextMajor(from: "2.27.0")
        ),
    ],
    targets: [
        .target(
            name: "SnapCompanionApp",
            destinations: .macOS,
            product: .app,
            bundleId: "br.com.anykey.SnapSync",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .file(path: "Packaging/Info.plist"),
            sources: ["Sources/SnapCompanionApp/**"],
            resources: ["Sources/SnapCompanionApp/Resources/**"],
            entitlements: .file(path: "Packaging/SnapCompanion.entitlements"),
            dependencies: [
                .package(product: "SnapSyncCore"),
                .package(product: "Kingfisher"),
                .target(name: "SnapCompanionProxy"),
            ],
            settings: .settings(base: [
                "PRODUCT_NAME": "SnapCompanion",
                "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
                "SWIFT_VERSION": "6.0",
            ])
        ),
        .target(
            name: "SnapCompanionProxy",
            destinations: .macOS,
            product: .systemExtension,
            bundleId: "br.com.anykey.SnapSync.proxy",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .file(path: "Packaging/SnapCompanionProxy-Info.plist"),
            sources: ["Sources/SnapCompanionProxy/*.swift"],
            resources: ["Sources/SnapCompanionProxy/Resources/**"],
            entitlements: .file(path: "Packaging/SnapCompanionProxy.entitlements"),
            dependencies: [
                .package(product: "NIOCore"),
                .package(product: "NIOSSL"),
                .package(product: "NIOHTTP1"),
                .package(product: "NIOWebSocket"),
            ],
            settings: .settings(base: [
                "PRODUCT_NAME": "br.com.anykey.SnapSync.proxy",
                "SWIFT_VERSION": "6.0",
            ])
        ),
    ]
)
