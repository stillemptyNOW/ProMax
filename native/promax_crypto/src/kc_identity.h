#ifndef KC_IDENTITY_H
#define KC_IDENTITY_H

#include <stddef.h>
#include <stdint.h>

#include "promax_crypto.h"

kc_status kc_identity_check(const uint8_t *identity, size_t identity_len);
void kc_identity_x25519_secret(const uint8_t *identity, uint8_t out[32]);
void kc_identity_x25519_public(const uint8_t eddsa_public[32],
                               uint8_t out[32]);
void kc_identity_sign(const uint8_t *identity,
                      const uint8_t *message,
                      size_t message_len,
                      uint8_t out_signature[64]);
int kc_identity_verify(const uint8_t eddsa_public[32],
                       const uint8_t *message,
                       size_t message_len,
                       const uint8_t signature[64]);

#endif
