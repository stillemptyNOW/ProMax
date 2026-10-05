#ifndef KC_INTERNAL_H
#define KC_INTERNAL_H

#include "promax_crypto.h"

#define KC_MAGIC 0x4Bu
#define KC_MESSAGE_VERSION 0x01u
#define KC_IMAGE_VERSION 0x02u
#define KC_MESSAGE_HEADER_SIZE 2u
#define KC_IMAGE_HEADER_SIZE 6u

#define KC_V3_VERSION 0x03u
#define KC_V3_OFFER 0x01u
#define KC_V3_ANSWER 0x02u
#define KC_V3_HEADER_SIZE 40u
#define KC_V3_ENVELOPE_MIN (KC_V3_HEADER_SIZE + 32u + KC_TAG_SIZE)
#define KC_V3_PAD_BLOCK 32u
#define KC_V3_MAX_SKIP KC_SESSION_MAX_SKIP
#define KC_V3_MAX_ADVANCE KC_SESSION_MAX_ADVANCE
#define KC_V3_MAX_SKIP_ENTRIES 256u

size_t kc_alphabet_encode_bound(size_t input_len);
kc_status kc_alphabet_encode(const uint8_t *input,
                             size_t input_len,
                             uint8_t *out,
                             size_t out_cap,
                             size_t *out_len);
kc_status kc_alphabet_decode(const uint8_t *text,
                             size_t text_len,
                             uint8_t **out,
                             size_t *out_len);
int kc_utf8_valid(const uint8_t *input, size_t input_len);
int kc_size_add(size_t left, size_t right, size_t *out);

kc_status kc_seal(const uint8_t *plaintext,
                  size_t plaintext_len,
                  const uint8_t *key,
                  size_t key_len,
                  const uint8_t *nonce,
                  size_t nonce_len,
                  const uint8_t *header,
                  size_t header_len,
                  uint8_t *out,
                  size_t out_cap,
                  size_t *out_len);
kc_status kc_open(const uint8_t *sealed,
                  size_t sealed_len,
                  const uint8_t *key,
                  size_t key_len,
                  const uint8_t *nonce,
                  const uint8_t *header,
                  size_t header_len,
                  uint8_t *out,
                  size_t out_cap,
                  size_t *out_len);

kc_status kc_handshake_decode(const uint8_t *text,
                              size_t text_len,
                              uint8_t out[KC_HANDSHAKE_SIZE]);

#endif
