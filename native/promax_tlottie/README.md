# promax_tlottie

Local FFI plugin that ships [tlottie](https://github.com/dkaraush/tlottie) — a Lottie
renderer written in Rust — to every native ProMax build. It carries only the native
library and its raw bindings (`TlottieBindings`); playback, the isolate pool and the
frame caches live in the app under `lib/core/media/tlottie/`.

## How it is built

`rust/` is a wrapper crate that depends on tlottie by an exact git `rev` with the
`c-api` feature and builds it as `cdylib` + `staticlib`, so the `tlottie_*` symbols of
the C ABI end up in `libpromax_tlottie`. `cargokit/` is vendored from `fjs` 3.3.0 (the
copy that also aligns Android arm64/x86_64 ELF segments to 16 KB pages) and compiles the
crate during the Flutter build with the same toolchain as `kolibri` and `fjs`;
`cargokit_options.yaml` at the app root keeps it building from source.

| Platform | Artifact | Loaded via |
|----------|----------|------------|
| Android  | `libpromax_tlottie.so` per ABI, packaged into the APK | `DynamicLibrary.open('libpromax_tlottie.so')` |
| Linux    | `libpromax_tlottie.so` in the bundle's `lib/` | `DynamicLibrary.open('libpromax_tlottie.so')` |
| Windows  | `promax_tlottie.dll` next to the executable | `DynamicLibrary.open('promax_tlottie.dll')` |
| iOS / macOS | `libpromax_tlottie.a`, `-force_load`ed into the pod | `DynamicLibrary.process()`, falling back to `promax_tlottie.framework` |

Web has no native path; the app plays animations with the pure-Dart `lottie` package there.

## Bumping tlottie

Change `rev` in `rust/Cargo.toml`, run `cargo update -p tlottie` in `rust/`, and check
that `tlottie.h` upstream still matches the signatures in `lib/promax_tlottie.dart`.
