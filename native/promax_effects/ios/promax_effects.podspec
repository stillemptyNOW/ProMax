Pod::Spec.new do |s|
  s.name = 'promax_effects'
  s.version = '0.1.0'
  s.summary = 'Outgoing call effects for ProMax'
  s.description = 'Real time audio processing and face overlays for outgoing WebRTC tracks.'
  s.homepage = 'https://github.com/stillemptyNOW/ProMax'
  s.license = { :type => 'GPL-3.0-or-later', :file => '../../../LICENSE' }
  s.author = 'ProMax contributors'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,mm}'
  s.public_header_files = 'Classes/ProMaxEffectsPlugin.h'
  s.dependency 'Flutter'
  s.dependency 'flutter_webrtc'
  s.ios.deployment_target = '15.0'
  s.frameworks = 'CoreImage', 'CoreVideo', 'UIKit'
  s.pod_target_xcconfig = { 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17' }
end
