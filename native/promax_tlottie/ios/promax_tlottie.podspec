Pod::Spec.new do |s|
  s.name             = 'promax_tlottie'
  s.version          = '0.1.0'
  s.summary          = 'tlottie Lottie renderer for ProMax.'
  s.description      = <<-DESC
Builds the tlottie C ABI with cargokit and links it into the app, where dart:ffi reaches it.
                       DESC
  s.homepage         = 'https://github.com/dkaraush/tlottie'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ProMax' => 'stillemptyNOW@users.noreply.github.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust promax_tlottie',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/libpromax_tlottie.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libpromax_tlottie.a',
  }
end
