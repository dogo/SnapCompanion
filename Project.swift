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
        .remote(
            url: "https://github.com/apple/swift-certificates.git",
            requirement: .upToNextMajor(from: "1.0.0")
        ),
        .remote(
            url: "https://github.com/apple/swift-crypto.git",
            requirement: .upToNextMajor(from: "3.0.0")
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
            scripts: [
                .pre(
                    script: """
                    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
                    cd "$SRCROOT"
                    mise exec -- swiftformat --lint --cache ignore Sources Tests Package.swift Project.swift Tuist.swift
                    touch "$SCRIPT_OUTPUT_FILE_0"
                    """,
                    name: "SwiftFormat",
                    inputPaths: [
                        ".swiftformat",
                        "mise.toml",
                        "Package.swift",
                        "Project.swift",
                        "Tuist.swift",
                        "Sources/**/*.swift",
                        "Tests/**/*.swift",
                    ],
                    outputPaths: ["$(DERIVED_FILE_DIR)/swiftformat-lint"],
                    basedOnDependencyAnalysis: true
                ),
            ],
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
            entitlements: .file(path: "Packaging/SnapCompanionProxy.entitlements"),
            dependencies: [
                .package(product: "NIOCore"),
                .package(product: "NIOSSL"),
                .package(product: "NIOHTTP1"),
                .package(product: "NIOWebSocket"),
                .package(product: "X509"),
                .package(product: "Crypto"),
            ],
            settings: .settings(base: [
                "PRODUCT_NAME": "br.com.anykey.SnapSync.proxy",
                "SWIFT_VERSION": "6.0",
            ])
        ),
    ]
)
