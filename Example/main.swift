import SwiftMsgpack

let input: [Double: String] = [3.14159265359: "pi", 1.41421356237: "sqrt(2)"]

let data = try! MsgPackEncoder().encode(input)
let out = try! MsgPackDecoder().decode([Double: String].self, from: data)

print([UInt8](data))
print(out)
// [130, 203, 63, 246, 160, 158, 102, 127, 5, 90, 167, 115, 113, 114, 116, 40, 50, 41, 203, 64, 9, 33, 251, 84, 68, 46, 234, 162, 112, 105]
// [3.14159265359: "pi", 1.41421356237: "sqrt(2)"]
