// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "VoiceKeyboardCore",
  platforms: [
    .macOS(.v13),
    .iOS(.v16)
  ],
  products: [
    .library(name: "VoiceKeyboardCore", targets: ["VoiceKeyboardCore"])
  ],
  targets: [
    .target(
      name: "VoiceKeyboardCore"
    ),
    .testTarget(
      name: "VoiceKeyboardCoreTests",
      dependencies: ["VoiceKeyboardCore"]
    )
  ]
)

