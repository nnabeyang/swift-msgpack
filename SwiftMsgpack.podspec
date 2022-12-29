Pod::Spec.new do |s|
  s.name         = "SwiftMsgpack"
  s.version      = "0.2.2"
  s.summary      = "swift-msgpack is a library of MessagePack encoder & decoder for Swift based on Codable."
  s.homepage              = "https://github.com/nnabeyang/swift-msgpack"
  s.license               = { :type => "MIT", :file => "LICENSE" }
  s.author                = { "Noriaki Watanabe" => "nabeyang@gmail.com" }
  s.ios.deployment_target = "13.0"
  s.osx.deployment_target = "10.15"

  s.source       = { :git => "https://github.com/nnabeyang/swift-msgpack.git", :tag => "#{s.version}" }
  s.source_files  = "Sources/**/*.swift"
  s.requires_arc = true
  s.swift_version = '5.6'
end
