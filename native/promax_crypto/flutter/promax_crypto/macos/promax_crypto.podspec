core_root = File.expand_path('../../..', File.realpath(__dir__))

Pod::Spec.new do |s|
  s.name             = 'promax_crypto'
  s.version          = '0.2.0'
  s.summary          = 'ProMax message-encryption core.'
  s.description      = <<-DESC
C core over monocypher: legacy passphrase scheme and v2 end-to-end encryption.
                       DESC
  s.homepage         = 'https://github.com/stillemptyNOW/ProMax'
  s.license          = { :type => 'MIT' }
  s.author           = { 'ProMax' => 'stillemptyNOW@users.noreply.github.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => "\"#{core_root}/include\" \"#{core_root}/src\" \"#{core_root}/third_party/monocypher\"",
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) KC_BUILDING=1',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'YES',
  }
  s.swift_version = '5.0'
end
