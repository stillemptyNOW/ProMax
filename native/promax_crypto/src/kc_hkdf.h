#ifndef KC_HKDF_H
#define KC_HKDF_H

#include <stddef.h>
#include <stdint.h>

void kc_hkdf(const uint8_t *salt,
             size_t salt_len,
             const uint8_t *ikm,
             size_t ikm_len,
             const uint8_t *info,
             size_t info_len,
             uint8_t *out,
             size_t out_len);

void kc_kdf_root(const uint8_t root[32],
                 const uint8_t dh[32],
                 uint8_t out_root[32],
                 uint8_t out_chain[32]);

void kc_kdf_chain(const uint8_t chain[32],
                  uint8_t out_chain[32],
                  uint8_t out_message[32]);

void kc_kdf_message(const uint8_t message_key[32],
                    uint8_t out_key[32],
                    uint8_t out_nonce[12]);

#endif
