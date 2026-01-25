# swift-msgpack

[![Linux](https://img.shields.io/badge/platform-linux-blue.svg)](https://github.com/nnabeyang/swift-msgpack)
[![iOS](https://img.shields.io/badge/platform-iOS-lightgrey.svg)](https://github.com/nnabeyang/swift-msgpack)
[![macOS](https://img.shields.io/badge/platform-macOS-black.svg)](https://github.com/nnabeyang/swift-msgpack)

[MessagePack](http://msgpack.org) is an efficient binary serialization format that lets you exchange data among multiple languages like JSON but in a more compact and faster form.  
Small integers can be encoded in a single byte, and short strings require only a prefix plus the original byte array.  
MessagePack implementations are available in various languages (see the list on http://msgpack.org).  
For the specification, see https://github.com/msgpack/msgpack/blob/master/spec.md.

**MessagePack implementation for Swift**  
This repository provides a **MessagePack encoder and decoder for Swift** that integrates with the Swift `Codable` API.

## Features

- Encodes and decodes Swift types using the `Codable` protocol
- Seamless integration with **Swift Package Manager**
- Compatible with **Swift 6**
- Works on **Linux, iOS, and macOS**
- Published under the **MIT License**

## Usage

```swift
import SwiftMsgpack

struct Coordinate: Codable {
    let latitude: Double
    let longitude: Double
}

struct Landmark: Codable {
    let name: String
    let foundingYear: Int
    let location: Coordinate
}

let input = Landmark(
    name: "Mojave Desert",
    foundingYear: 0,
    location: Coordinate(
        latitude: 35.0110079,
        longitude: -115.4821313
    )
)
let encoder = MsgPackEncoder()
let decoder = MsgPackDecoder()
let data = try! encoder.encode(input)
let out = try! decoder.decode(Landmark.self, from: data)
let any = try! decoder.decode(AnyCodable.self, from: data)

print([UInt8](data))
// [131, 164, 110, 97, 109, 101, 173, 77, 111, 106,
//  97, 118, 101, 32, 68, 101, 115, 101, 114, 116,
//  172, 102, 111, 117, 110, 100, 105, 110, 103, 89,
//  101, 97, 114, 0, 168, 108, 111, 99, 97, 116,
//  105, 111, 110, 130, 168, 108, 97, 116, 105, 116,
//  117, 100, 101, 203, 64, 65, 129, 104, 180, 245,
//  63, 179, 169, 108, 111, 110, 103, 105, 116, 117,
//  100, 101, 203, 192, 92, 222, 219, 61, 61, 120,
//  49]

print(out)
// Landmark(
//   name: "Mojave Desert",
//   foundingYear: 0,
//   location: example.Coordinate(
//     latitude: 35.0110079,
//     longitude: -115.4821313
//   )
// )

print(any)
// AnyCodable(
//     [
//         AnyCodable("foundingYear"): AnyCodable(0),
//         AnyCodable("name"): AnyCodable("Mojave Desert"),
//         AnyCodable("location"): AnyCodable(
//             [
//                 AnyCodable("longitude"): AnyCodable(-115.4821313),
//                 AnyCodable("latitude"): AnyCodable(35.0110079),
//             ]
//         ),
//     ]
// )
```

## Installation

### Swift Package Manager

To use swift-msgpack in your Swift project, add it as a dependency in your Package.swift:

```swift
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        // other dependencies
        .package(url: "https://github.com/nnabeyang/swift-msgpack", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(name: "<executable-target-name>", dependencies: [
            // other dependencies
                .product(name: "SwiftMsgpack", package: "swift-msgpack"),
        ]),
        // other targets
    ]
)
```

### CocoaPods

Add the following to your Podfile:

```terminal
pod 'SwiftMessagePack'
```
## License

swift-msgpack is published under the MIT License. See the LICENSE file for details.

## Author
[Noriaki Watanabe@nnabeyang](https://bsky.app/profile/did:plc:bnh3bvyqr3vzxyvjdnrrusbr)

## About

swift-msgpack is a library of MessagePack encoder & decoder for Swift based on Codable, following the same design principles as Swift’s built-in JSON support.
