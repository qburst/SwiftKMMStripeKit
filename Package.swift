// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftKMMStripeKit",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SwiftKMMStripeKit",
            targets: ["SwiftKMMStripeKit"])
    ],
    
    dependencies: [
        // Add stripe-ios-spm as a dependency
        .package(
            url: "https://github.com/stripe/stripe-ios-spm.git",
            from: "23.29.2" // Use the latest version or the specific version you need
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftKMMStripeKit",
            dependencies: [
                .product(name: "Stripe", package: "stripe-ios-spm"),
                .product(name: "StripePaymentSheet", package: "stripe-ios-spm") // Explicitly add StripePaymentSheet
            ]
        ),
        .testTarget(
            name: "SwiftKMMStripeKitTests",
            dependencies: ["SwiftKMMStripeKit"])
    ]
)
