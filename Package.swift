// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
//--------------------------------------------------------------------------------------------------

import PackageDescription

//--------------------------------------------------------------------------------------------------

let package = Package (
  name: "SerialPort",
  platforms: [.macOS (.v15)],
  products: [
    .library (name: "SerialPort", targets: ["SerialPort"])
  ],
  targets: [
    .target (name: "SerialPort")
  ]
)

//--------------------------------------------------------------------------------------------------
