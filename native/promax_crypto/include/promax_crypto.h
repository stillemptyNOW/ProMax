#ifndef PROMAX_CRYPTO_H
#define PROMAX_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(KC_STATIC)
#define KC_EXPORT
#elif defined(KC_BUILDING)
#define KC_EXPORT __declspec(dllexport)
#else
#define KC_EXPORT __declspec(dllimport)
#endif
#else
#define KC_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#if defined(__cplusplus)
extern "C" {
#endif

#define KC_KEY_SIZE 32u
#define KC_NONCE_SIZE 12u
#define KC_TAG_SIZE 16u

#define KC_SEED_SIZE 32u
#define KC_PUBLIC_KEY_SIZE 32u
#define KC_IDENTITY_SIZE 64u
#define KC_FINGERPRINT_DIGITS 60u
#define KC_OFFER_ID_SIZE 8u
#define KC_HANDSHAKE_SIZE 138u
#define KC_HANDSHAKE_TEXT_BOUND 497u
#define KC_PENDING_STATE_SIZE 203u
#define KC_SESSION_STATE_MAX 17712u
#define KC_SESSION_PLAINTEXT_MAX 414u
#define KC_SESSION_MAX_SKIP 256u
#define KC_SESSION_MAX_ADVANCE 65536u
#define KC_TEXT_TRANSPORT_MAX 1000u

#define KC_IDENTITY_RANDOM_SIZE 32u
#define KC_OFFER_RANDOM_SIZE 40u
#define KC_ANSWER_RANDOM_SIZE 32u
#define KC_ACCEPT_RANDOM_SIZE 32u
#define KC_ENCRYPT_RANDOM_SIZE 32u
#define KC_EXPORT_RANDOM_SIZE 40u

#define KC_CONTENT_TEXT 1u
#define KC_CONTENT_FILE 2u
#define KC_CONTENT_CONTROL 3u

#define KC_FILE_KEY_SIZE 32u
#define KC_FILE_NONCE_SIZE 12u
#define KC_FILE_CHUNK_SIZE 65536u
#define KC_FILE_CTX_SIZE 96u

#define KC_LOCAL_KEY_SIZE 32u
#define KC_LOCAL_NONCE_SIZE 24u

#define KC_TEXT_NONE 0
#define KC_TEXT_LEGACY 1
#define KC_TEXT_OFFER 2
#define KC_TEXT_ANSWER 3
#define KC_TEXT_SESSION 4

typedef enum {
    KC_OK = 0,
    KC_ERR_EMPTY_PASSWORD = -1,
    KC_ERR_BAD_KEY_LENGTH = -2,
    KC_ERR_NOT_ENCRYPTED = -3,
    KC_ERR_MALFORMED = -4,
    KC_ERR_WRONG_KEY = -5,
    KC_ERR_INTERNAL = -6,
    KC_ERR_BUFFER_TOO_SMALL = -7,
    KC_ERR_INVALID_ARGUMENT = -8,
    KC_ERR_OUT_OF_MEMORY = -9,
    KC_ERR_BAD_SIGNATURE = -10,
    KC_ERR_BAD_STATE = -11,
    KC_ERR_TOO_MANY_SKIPPED = -12,
    KC_ERR_REPLAY = -13,
    KC_ERR_BAD_PEER = -14,
    KC_ERR_UNSUPPORTED_VERSION = -15,
    KC_ERR_HANDSHAKE_MESSAGE = -16,
    KC_ERR_TOO_LONG = -17,
    KC_ERR_AWAITING_PEER = -18
} kc_status;

KC_EXPORT const char *kc_status_string(kc_status status);

KC_EXPORT void kc_wipe(void *buf, size_t len);

KC_EXPORT kc_status kc_derive_key(const uint8_t *password,
                                  size_t password_len,
                                  uint8_t *out_key,
                                  size_t out_key_len);

KC_EXPORT size_t kc_encrypt_message_bound(size_t plaintext_len);

KC_EXPORT kc_status kc_encrypt_message(const uint8_t *plaintext,
                                       size_t plaintext_len,
                                       const uint8_t *key,
                                       size_t key_len,
                                       const uint8_t *nonce,
                                       size_t nonce_len,
                                       uint8_t *out,
                                       size_t out_cap,
                                       size_t *out_len);

KC_EXPORT size_t kc_decrypt_message_bound(size_t text_len);

KC_EXPORT kc_status kc_decrypt_message(const uint8_t *text,
                                       size_t text_len,
                                       const uint8_t *key,
                                       size_t key_len,
                                       uint8_t *out,
                                       size_t out_cap,
                                       size_t *out_len);

KC_EXPORT int kc_looks_encrypted_message(const uint8_t *text, size_t text_len);

KC_EXPORT size_t kc_encrypt_image_blob_bound(size_t plaintext_len);

KC_EXPORT kc_status kc_encrypt_image_blob(const uint8_t *plaintext,
                                          size_t plaintext_len,
                                          const uint8_t *key,
                                          size_t key_len,
                                          const uint8_t *nonce,
                                          size_t nonce_len,
                                          uint8_t *out,
                                          size_t out_cap,
                                          size_t *out_len);

KC_EXPORT size_t kc_decrypt_image_blob_bound(size_t blob_len);

KC_EXPORT kc_status kc_decrypt_image_blob(const uint8_t *blob,
                                          size_t blob_len,
                                          const uint8_t *key,
                                          size_t key_len,
                                          uint8_t *out,
                                          size_t out_cap,
                                          size_t *out_len);

KC_EXPORT int kc_looks_encrypted_image_blob(const uint8_t *blob,
                                            size_t blob_len);

KC_EXPORT kc_status kc_identity_create(const uint8_t *seed,
                                       size_t seed_len,
                                       uint8_t *out_identity,
                                       size_t out_cap,
                                       size_t *out_len);

KC_EXPORT kc_status kc_identity_public_key(const uint8_t *identity,
                                           size_t identity_len,
                                           uint8_t *out_public,
                                           size_t out_cap,
                                           size_t *out_len);

KC_EXPORT kc_status kc_fingerprint(int64_t my_id,
                                   const uint8_t *my_public,
                                   size_t my_public_len,
                                   int64_t peer_id,
                                   const uint8_t *peer_public,
                                   size_t peer_public_len,
                                   uint8_t *out_digits,
                                   size_t out_cap,
                                   size_t *out_len);

KC_EXPORT int kc_classify_text(const uint8_t *text, size_t text_len);

KC_EXPORT kc_status kc_handshake_peek(const uint8_t *text,
                                      size_t text_len,
                                      uint8_t *out_type,
                                      uint8_t *out_offer_id,
                                      size_t offer_id_cap,
                                      uint8_t *out_public,
                                      size_t public_cap);

KC_EXPORT kc_status kc_session_offer(const uint8_t *identity,
                                     size_t identity_len,
                                     int64_t chat_id,
                                     int64_t my_id,
                                     int64_t peer_id,
                                     const uint8_t *random,
                                     size_t random_len,
                                     uint8_t *out_text,
                                     size_t text_cap,
                                     size_t *text_len,
                                     uint8_t *out_pending,
                                     size_t pending_cap,
                                     size_t *pending_len);

KC_EXPORT kc_status kc_session_answer(const uint8_t *identity,
                                      size_t identity_len,
                                      int64_t chat_id,
                                      int64_t my_id,
                                      int64_t peer_id,
                                      const uint8_t *offer_text,
                                      size_t offer_len,
                                      const uint8_t *old_state,
                                      size_t old_state_len,
                                      const uint8_t *random,
                                      size_t random_len,
                                      uint8_t *out_text,
                                      size_t text_cap,
                                      size_t *text_len,
                                      uint8_t *out_state,
                                      size_t state_cap,
                                      size_t *state_len);

KC_EXPORT kc_status kc_session_accept(const uint8_t *identity,
                                      size_t identity_len,
                                      const uint8_t *pending,
                                      size_t pending_len,
                                      const uint8_t *answer_text,
                                      size_t answer_len,
                                      const uint8_t *expected_peer,
                                      size_t expected_peer_len,
                                      const uint8_t *random,
                                      size_t random_len,
                                      uint8_t *out_state,
                                      size_t state_cap,
                                      size_t *state_len);

KC_EXPORT size_t kc_session_encrypt_bound(size_t plaintext_len);

KC_EXPORT kc_status kc_session_encrypt(const uint8_t *state,
                                       size_t state_len,
                                       uint8_t content_type,
                                       const uint8_t *plaintext,
                                       size_t plaintext_len,
                                       const uint8_t *random,
                                       size_t random_len,
                                       uint8_t *out_text,
                                       size_t text_cap,
                                       size_t *text_len,
                                       uint8_t *out_state,
                                       size_t state_cap,
                                       size_t *state_out_len);

KC_EXPORT size_t kc_session_decrypt_bound(size_t text_len);

KC_EXPORT kc_status kc_session_decrypt(const uint8_t *state,
                                       size_t state_len,
                                       const uint8_t *text,
                                       size_t text_len,
                                       uint8_t *out_content_type,
                                       uint8_t *out_plaintext,
                                       size_t plaintext_cap,
                                       size_t *plaintext_len,
                                       uint8_t *out_state,
                                       size_t state_cap,
                                       size_t *state_out_len);

KC_EXPORT kc_status kc_session_peer_public_key(const uint8_t *state,
                                               size_t state_len,
                                               uint8_t *out_public,
                                               size_t out_cap,
                                               size_t *out_len);

KC_EXPORT size_t kc_file_seal_bound(size_t plaintext_len);

KC_EXPORT size_t kc_file_open_bound(size_t ciphertext_len);

KC_EXPORT kc_status kc_file_seal_init(uint8_t *ctx,
                                      size_t ctx_len,
                                      const uint8_t *key,
                                      size_t key_len,
                                      const uint8_t *nonce,
                                      size_t nonce_len);

KC_EXPORT kc_status kc_file_seal_chunk(uint8_t *ctx,
                                       size_t ctx_len,
                                       const uint8_t *plaintext,
                                       size_t plaintext_len,
                                       int last,
                                       uint8_t *out,
                                       size_t out_cap,
                                       size_t *out_len);

KC_EXPORT kc_status kc_file_open_init(uint8_t *ctx,
                                      size_t ctx_len,
                                      const uint8_t *key,
                                      size_t key_len,
                                      const uint8_t *nonce,
                                      size_t nonce_len);

KC_EXPORT kc_status kc_file_open_chunk(uint8_t *ctx,
                                       size_t ctx_len,
                                       const uint8_t *chunk,
                                       size_t chunk_len,
                                       int last,
                                       uint8_t *out,
                                       size_t out_cap,
                                       size_t *out_len);

KC_EXPORT size_t kc_local_seal_bound(size_t plaintext_len);

KC_EXPORT size_t kc_local_open_bound(size_t blob_len);

KC_EXPORT kc_status kc_local_seal(const uint8_t *key,
                                  size_t key_len,
                                  const uint8_t *nonce,
                                  size_t nonce_len,
                                  const uint8_t *aad,
                                  size_t aad_len,
                                  const uint8_t *plaintext,
                                  size_t plaintext_len,
                                  uint8_t *out,
                                  size_t out_cap,
                                  size_t *out_len);

KC_EXPORT kc_status kc_local_open(const uint8_t *key,
                                  size_t key_len,
                                  const uint8_t *aad,
                                  size_t aad_len,
                                  const uint8_t *blob,
                                  size_t blob_len,
                                  uint8_t *out,
                                  size_t out_cap,
                                  size_t *out_len);

KC_EXPORT size_t kc_export_seal_bound(size_t container_len);

KC_EXPORT size_t kc_export_open_bound(size_t blob_len);

KC_EXPORT kc_status kc_export_seal(const uint8_t *password,
                                   size_t password_len,
                                   uint32_t memory_kib,
                                   uint32_t passes,
                                   const uint8_t *random,
                                   size_t random_len,
                                   const uint8_t *container,
                                   size_t container_len,
                                   uint8_t *out,
                                   size_t out_cap,
                                   size_t *out_len);

KC_EXPORT kc_status kc_export_open(const uint8_t *password,
                                   size_t password_len,
                                   const uint8_t *blob,
                                   size_t blob_len,
                                   uint8_t *out_container,
                                   size_t out_cap,
                                   size_t *out_len);

#if defined(__cplusplus)
}
#endif

#endif
