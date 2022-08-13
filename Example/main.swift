import SwiftMsgpack

struct Coordinate: Codable {
    var latitude: Double
    var longitude: Double
}

struct Landmark: Codable {
    var name: String
    var foundingYear: Int
    var location: Coordinate
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
// [131, 164, 110, 97, 109, 101, 173, 77, 111, 106, 97, 118, 101, 32, 68, 101, 115, 101, 114, 116, 172, 102, 111, 117, 110, 100, 105, 110, 103, 89, 101, 97, 114, 0, 168, 108, 111, 99, 97, 116, 105, 111, 110, 130, 168, 108, 97, 116, 105, 116, 117, 100, 101, 203, 64, 65, 129, 104, 180, 245, 63, 179, 169, 108, 111, 110, 103, 105, 116, 117, 100, 101, 203, 192, 92, 222, 219, 61, 61, 120, 49]

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
//   [
//     AnyCodable(location): AnyCodable(
//       [
//         AnyCodable(longitude): AnyCodable(-115.4821313),
//         AnyCodable(latitude): AnyCodable(35.0110079)
//       ]
//     ),
//     AnyCodable(foundingYear): AnyCodable(0),
//     AnyCodable(name): AnyCodable(Mojave Desert)
//   ]
// )
