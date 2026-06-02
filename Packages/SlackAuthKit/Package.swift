// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SlackAuthKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SlackAuthKit", targets: ["SlackAuthKit"])
  ],
  targets: [
    .target(name: "SlackAuthKit"),
    .testTarget(name: "SlackAuthKitTests", dependencies: ["SlackAuthKit"]),
  ],
  swiftLanguageModes: [.v6]
)
