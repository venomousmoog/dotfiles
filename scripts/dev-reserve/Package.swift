// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DevReserve",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "DevReserve", targets: ["DevReserve"])
  ],
  targets: [
    .target(name: "DevReserveCore"),
    .executableTarget(
      name: "DevReserve",
      dependencies: ["DevReserveCore"]
    ),
    .executableTarget(
      name: "DevReserveSelfTest",
      dependencies: ["DevReserveCore"],
      path: "SelfTest"
    ),
  ]
)
