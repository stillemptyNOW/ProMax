# ProMax encryption protocol

All integers below are unsigned big-endian unless explicitly described as signed
64-bit chat/user identifiers. Identifiers use their two's-complement big-endian
representation. Byte strings are not NUL terminated. Monocypher's EdDSA uses
Ed25519 with BLAKE2b, **not** RFC 8032 Ed25519 with SHA-512. Implementations must
use the vendored native core, including its identity, KDF and codec functions.

## Existing pairwise protocol (v3, unchanged)

An identity is a 64-byte Monocypher EdDSA secret key: 32-byte seed followed by
32-byte public key. It must be stored with the platform's protected key storage.
The decimal safety number binds both user identifiers and identity public keys;
the application must confirm identity changes with the user.

Handshake binary records are exactly 138 bytes:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 1 | Version `03` |
| 1 | 1 | Type: offer `01`, answer `02` |
| 2 | 8 | Random offer identifier |
| 10 | 32 | Sender identity public key |
| 42 | 32 | Ephemeral X25519 Elligator representative |
| 74 | 64 | EdDSA signature |

The offer signature covers ASCII `promax-v3/offer`, chat ID, sender ID,
recipient ID and bytes 0..73. The answer signature covers ASCII
`promax-v3/answer`, chat ID, sender ID, recipient ID, bytes 0..73 and
BLAKE2b-256 of the complete offer. The answer repeats the offer identifier.
The initiator verifies a pinned recipient identity when supplied.

The handshake computes three X25519 shared secrets. The KDF input is 32 bytes
of `FF`, then DH1, DH2 and DH3. KDF info is ASCII `promax-v3/sk` followed by
BLAKE2b-256(offer || answer). The native BLAKE2b HKDF-like construction derives
96 bytes: root key, initial chain key, and envelope-counter masking key.
This construction is defined by `src/kc_hkdf.c`; it is not RFC 5869 HMAC-SHA256.
Reject all-zero X25519 shared secrets.

Pairwise encrypted envelopes have a 40-byte header: 32-byte sender ratchet
Elligator representative and eight masked bytes encoding previous-chain length
and message number (two u32 values). The AEAD associated data is version `03`,
chat ID, sender ID, representative and **unmasked** counters. The mask is the
eight-byte keyed BLAKE2b output over representative || Poly1305 tag, with the
masking key from the handshake. ChaCha20-Poly1305-IETF encrypts the body and
appends its 16-byte tag. A chain step derives a message key using keyed
BLAKE2b-256(chain, `01`) and the next chain using keyed BLAKE2b-256(chain, `02`).
Message-key expansion uses info `promax-v3/mk` and derives a 32-byte AEAD key
and a 12-byte nonce. DH root-key expansion uses info `promax-v3/rk`.

The plaintext body is content type (`01` text, `02` file, `03` control), payload,
`80`, then zero padding. Padding buckets are 32, 64, 128, 256 and 416 bytes for
the supported maximum 414-byte payload. Envelopes and handshakes use the
native alphabet codec in `src/kc_alphabet.c`, not Base64. Maximum text transport
is 1000 Unicode characters (the UTF-8 buffer can be longer). The receiver stores at most 256 skipped message keys and refuses
more than 65536 chain steps per receive operation. Authentication failure must
not commit the returned ratchet state.

Legacy password messages remain readable: magic `4B`, version `01`, 12-byte
nonce, ciphertext and 16-byte ChaCha20-Poly1305 tag; the two-byte header is AAD.
Legacy image blobs use magic `4B`, version `02`, four-byte payload length,
12-byte nonce, ciphertext and tag; the six-byte header is AAD. The encoded
length excludes the six-byte header and allows an outer carrier's trailing
padding. Password derivation and legacy alphabet behavior remain defined by
the existing vectors in `tests/vectors/v3.json` and core regression tests.

File encryption uses 65536-byte chunks with one 16-byte tag per chunk. AAD is
ASCII `promax-v3/file`, u32 chunk index and a last-chunk byte. The streaming
AEAD context advances between chunks. Local protected blobs use XChaCha20-
Poly1305, serialized as 24-byte nonce || ciphertext || 16-byte tag with caller
AAD. Neither local states nor sender-key distributions may be logged.

## Group sender-key extension G1

G1 is an independent binary protocol. It does not alter pairwise v3 wire formats.
The native API handles all cryptography and parsing. The application transports
the resulting opaque bytes; transport chunking is outside this specification.
There is one send state per local sender and one receive state per remote sender
and group epoch. Payloads are bounded to 65536 bytes.

### Preconditions and membership

The application must obtain the current authoritative MAX group membership,
verify each account's pinned ProMax identity using the Hub's account-attestation
mechanism, and require explicit group encryption consent from every member.
An arbitrary user ID, phone number or self-asserted public key is insufficient.
The native core does not establish these facts. Until this integration is
available and verified, G1 primitives must not be presented as enabled group E2EE.

The manifest is 2..256 records, sorted by strictly increasing positive user ID.
Each record is eight-byte user ID || 32-byte pinned identity public key.
Duplicate IDs, duplicate public keys and all-zero public keys are rejected.
The membership digest is BLAKE2b-256(ASCII `promax-group-v1/members` || group ID
|| manifest). Group IDs must be nonzero. Every sender must appear in the manifest
with the same identity key used for signing.

Any join, leave, identity change or consent withdrawal stops encrypted sending
immediately. Every retained sender creates a fresh random 32-byte chain seed in
the next epoch and distributes it only to the new verified, consenting manifest.
Old sender/receiver states and pending sends are invalidated. If any member lacks
ProMax/consent/verification, encryption remains disabled and the UI must explain
the reason before any unencrypted send. Never silently downgrade a pending
encrypted message to plaintext. Offline clients must revalidate membership
before sending. Epoch transitions require the application to agree on one
authoritative manifest/epoch; this native extension alone provides no group
consensus, transparency service, membership discovery or post-compromise recovery.

### Sender-key distribution

A distribution is exactly 188 bytes:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | Magic/version/type: `4B 47 01 01` |
| 4 | 8 | Group ID |
| 12 | 8 | Epoch (starts at 1, strictly increases) |
| 20 | 8 | Sender user ID |
| 28 | 32 | Membership digest |
| 60 | 32 | Sender identity public key |
| 92 | 32 | Initial sender chain seed (secret) |
| 124 | 64 | Signature |

The initial sender chain seed is derived from 32 fresh random bytes using the
native HKDF-like construction, with the membership digest as salt and info
ASCII `promax-group-v1/seed` || group ID || epoch || sender ID. A joining sender
with no earlier state starts at the group's current positive epoch. An existing
sender must advance by exactly one epoch; importing receivers may skip epochs.

The signature is over BLAKE2b-256(ASCII `promax-group-v1/distribution` || bytes
0..123), signed with the sender's pinned identity. This explicit prehash is
part of G1 and differs from the pairwise handshake's direct signing.

The distribution **contains the plaintext chain secret**. It must be transported
separately to each current member inside an authenticated pairwise v3 session
as a control payload. Never upload it unencrypted to Hub, send it to a removed
member, include it in a public group message, or persist it in unprotected logs.
Import checks signature, group, manifest digest and pinned sender identity.
Supplying an old receive state additionally rejects equal/older epochs; the
application must retain the highest accepted epoch independently of key cleanup
to prevent rollback after deletion, restore, logout or app restart.

### Encrypted group messages

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | Magic/version/type: `4B 47 01 02` |
| 4 | 8 | Group ID |
| 12 | 8 | Epoch |
| 20 | 8 | Sender user ID |
| 28 | 32 | Membership digest |
| 60 | 4 | Message counter (starts at zero) |
| 64 | variable | Ciphertext of content-type byte || payload |
| following | 16 | Poly1305 tag |
| following | 64 | Sender identity signature |

The 64-byte header is AEAD AAD. The chain step uses domain-separated keyed
BLAKE2b-256 with ASCII `promax-group-v1/message` and
`promax-group-v1/chain`. Expansion of a message key uses the native HKDF-like
construction, info `promax-group-v1/aead`, yielding 32-byte key and 12-byte nonce.
The signature signs BLAKE2b-256(ASCII `promax-group-v1/envelope` || header ||
ciphertext || tag), using the pinned sender identity. Verify it before deriving
skipped keys or decrypting. It prevents another group member, who knows the
sender chain secret, from impersonating that sender.

Only content types 1..3 are accepted. Counters never wrap. Receive states hold at
most 256 skipped keys, permit at most 256 new skipped messages in one operation,
and reject consumed counters. Auth/parse/capacity failure leaves input state
unchanged and produces no new usable state. Applications must atomically persist
the new sender state before sending and the new receive state with the accepted
message; retaining/reusing a send state repeats keys/nonces. Caller-supplied
randomness must come from the OS CSPRNG and never be reused across epochs.

State serialization is native-private, contains secrets and must be protected
with local AEAD. It is bounded by `KC_GROUP_STATE_MAX`. Never reimplement state
serialization in Dart or share it through settings exports. Sender-key chains
provide forward secrecy only for erased earlier message keys; compromise of a
current chain exposes future messages until fresh authenticated rotation.

`kc_group_members_build` serializes typed ID/public-key arrays in native code.
All output buffers must be distinct from each other and from identity/member/
distribution/envelope/plaintext inputs. The state output may alias its state
input; this in-place state replacement is covered by the native test suite.
