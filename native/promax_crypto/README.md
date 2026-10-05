# ProMax crypto core

Portable C99 message-encryption core of ProMax, built on the vendored
[monocypher 4.0.2](third_party/monocypher). It lives inside the ProMax
repository and is compiled directly by the Flutter plugin in
`flutter/promax_crypto`.

* **ProMax v3** — per-installation identity keys, X25519 handshake carried as
  ordinary chat messages, Double Ratchet (forward secrecy, post-compromise
  security), per-message counter masking, size-bucketed envelopes, chunked file
  encryption, sealed local storage, passphrase-protected device transfer.
  Formats: [docs/PROTOCOL.md](docs/PROTOCOL.md).
* **legacy (v1)** — shared-passphrase scheme for group chats.

The API is `include/promax_crypto.h`: stateless functions over caller-provided
buffers, `*_bound()` helpers for sizing, `kc_status` results. The core has no
RNG — every function that needs randomness takes it as an argument
(`KC_*_RANDOM_SIZE`). Session state is an opaque blob the caller stores.

## Build

```sh
make test            # build and run the suite
make asan            # AddressSanitizer + UBSan
make vectors         # regenerate tests/vectors/v3.json
make fuzz            # libFuzzer (needs clang with libFuzzer)
```

## Threat model in one paragraph

The MAX server is the adversary: it stores every message, can forge, drop,
delay or replay them, and knows all metadata. This core protects message and
file contents between two ProMax installations that completed a handshake, and
limits the damage of a later key compromise to the current ratchet window. It
does not hide that encryption is used, does not hide who talks to whom, cannot
prevent the server from suppressing delivery, and cannot detect an active
substitution of the very first handshake — only an out-of-band fingerprint
comparison can.
