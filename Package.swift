// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "admin-web",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        // 🍃 An expressive, performant, and extensible templating language.
        .package(url: "https://github.com/vapor/leaf.git", from: "4.3.0"),
        // 🔴 Redis-backed session storage, so sessions survive across replicas.
        .package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
        // 🔒 MD5 for the avatar menu's Gravatar URL - same use as catalog-web's.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1"),
        // 🩻 Distributed tracing API + OTLP exporter, matching the Go services' OTLP/HTTP
        // export to the cluster's Jaeger collector (docs/service-conventions.md's Telemetry
        // section).
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-otel/swift-otel.git", from: "0.8.0"),
        // 📊 Prometheus metrics.
        .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Redis", package: "redis"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Prometheus", package: "swift-prometheus"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "OTel", package: "swift-otel"),
                .product(name: "OTLPGRPC", package: "swift-otel"),
            ],
            // Resources/ is shipped as a plain directory next to the built binary (see
            // Dockerfile), not via SwiftPM resource bundling - Vapor's default Leaf resolution
            // looks for it relative to the working directory, not via Bundle.module.
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
    ]
)
