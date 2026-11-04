#!/usr/bin/env bash
set -euo pipefail

expected_certificate=e83be69ec2ea9cc8f418b533636c1a114824bfc05a940fca6060205f390d72b6
expected_package=io.github.stillemptynow.promax
expected_version=$(awk '/^version:/ {split($2, v, "+"); print v[1]; exit}' pubspec.yaml)
expected_code=$(awk '/^version:/ {split($2, v, "+"); print v[2]; exit}' pubspec.yaml)
build_tools=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)

for abi in arm64-v8a armeabi-v7a x86_64 universal; do
  apk="build/app/outputs/flutter-apk/app-$abi-promax-release.apk"
  if [ "$abi" = universal ]; then apk=build/app/outputs/flutter-apk/app-promax-release.apk; fi
  if ! certificates=$("$build_tools/apksigner" verify --print-certs "$apk"); then
    echo "::error::APK signature verification failed for $abi ($apk)."
    exit 1
  fi
  actual_certificate=$(printf '%s\n' "$certificates" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | tr '[:upper:]' '[:lower:]')
  signer_count=$(printf '%s\n' "$certificates" | grep -c '^Signer #[0-9]* certificate SHA-256 digest: ' || true)
  if [ "$signer_count" != 1 ]; then
    echo "::error::Expected one Android signer for $abi, found $signer_count."
    printf '%s\n' "$certificates" | sed -n '/[Ss]igner/p' | head -n 10
    exit 1
  fi
  if [ "$actual_certificate" != "$expected_certificate" ]; then
    echo "::error::Android signing certificate changed for $abi. Expected $expected_certificate; found ${actual_certificate:-unavailable}."
    exit 1
  fi
  if ! package=$("$build_tools/aapt" dump badging "$apk" | sed -n '/^package: /p'); then
    echo "::error::Could not read Android package metadata for $abi."
    exit 1
  fi
  if [[ "$package" != *"name='$expected_package'"* ]] || [[ "$package" != *"versionCode='$expected_code'"* ]] || [[ "$package" != *"versionName='$expected_version'"* ]]; then
    echo "::error::Unexpected Android package or version: $abi"
    exit 1
  fi
  echo "Verified $abi: permanent certificate, $expected_package, $expected_version+$expected_code"
done
