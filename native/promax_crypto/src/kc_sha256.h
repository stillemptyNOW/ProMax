#ifndef KC_SHA256_H
#define KC_SHA256_H

#include <stddef.h>
#include <stdint.h>

#define KC_SHA256_SIZE 32u

typedef struct {
    uint32_t state[8];
    uint64_t length;
    uint8_t buffer[64];
    size_t buffered;
} kc_sha256;

void kc_sha256_init(kc_sha256 *context);
void kc_sha256_update(kc_sha256 *context,
                      const uint8_t *input,
                      size_t input_len);
void kc_sha256_final(kc_sha256 *context, uint8_t out[KC_SHA256_SIZE]);

#endif
