Pod::Spec.new do |s|
  s.name          = "LiveAndAiChat"
  s.version       = "0.1.0"
  s.summary       = "LiveAndAiChat iOS SDK — native chat widget for cinstance.com."
  s.description   = <<~DESC
    Native Swift SDK that ports the LiveAndAiChat web widget to iOS:
    GraphQL transport over SSE / WebSocket, in-app chat UI, attachment
    handling, fine-grained appearance configuration. Drop-in equivalent
    of the Android `live-and-ai-chat-android` artifact.
  DESC
  s.homepage      = "https://cinstance.com"
  s.license       = { :type => "MIT" }
  s.author        = { "NewInstance" => "dev@cinstance.com" }
  s.platform      = :ios, "14.0"
  s.swift_version = "5.9"
  s.source        = { :git => "https://github.com/newinstance/live-and-ai-chat-ios.git", :tag => s.version.to_s }

  s.source_files  = "Sources/LiveAndAiChat/**/*.swift"
  s.frameworks    = "Foundation", "Combine", "Network"
end
