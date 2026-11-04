#!/usr/bin/env bash
set -euo pipefail

expected_certificate=e83be69ec2ea9cc8f418b533636c1a114824bfc05a940fca6060205f390d72b6
expected_package=io.github.stillemptynow.promax
expected_version=$(awk '/^version:/ {split($2, v, "+"); print v[1]; exit}' pubspec.yaml)
base_code=$(awk '/^version:/ {split($2, v, "+"); print v[2]; exit}' pubspec.yaml)
build_tools=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)

declare -A abi_version_multiplier=( [armeabi-v7a]=1 [arm64-v8a]=2 [x86_64]=4 )

for abi in arm64-v8a armeabi-v7a x86_64 universal; do
  apk="build/app/outputs/flutter-apk/app-$abi-promax-release.apk"
  expected_code=$base_code
  if [ "$abi" = universal ]; then
    apk=build/app/outputs/flutter-apk/app-promax-release.apk
  else
    expected_code=$((abi_version_multiplier[$abi] * 1000 + base_code))
  fi
  if ! certificates=$("$build_tools/apksigner" verify --print-certs "$apk"); then
    echo "::error::APK signature verification failed for $abi ($apk)."
    exit 1
  fi
  digests=$(printf '%s\n' "$certificates" | sed -n 's/^\(Signer #[0-9]*\|V[0-9][0-9.]* Signer\):\{0,1\} certificate SHA-256 digest: //p' | tr '[:upper:]' '[:lower:]' | sort -u)
  signer_count=$(printf '%s\n' "$digests" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$signer_count" != 1 ]; then
    echo "::error::Expected one Android signer for $abi, found $signer_count."
    printf '%s\n' "$certificates" | sed -n '/[Ss]igner/p' | head -n 10
    exit 1
  fi
  actual_certificate=$digests
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
