#include "kc_internal.h"

#include "monocypher.h"
#include <string.h>

void kc_wipe(void *buf, size_t len)
{
    if (buf != NULL && len != 0u) {
        crypto_wipe(buf, len);
    }
}

size_t kc_local_seal_bound(size_t plaintext_len)
{
    size_t result;

    if (!kc_size_add(plaintext_len, KC_LOCAL_NONCE_SIZE + KC_TAG_SIZE,
                     &result)) {
        return 0u;
    }
    return result;
}

size_t kc_local_open_bound(size_t blob_len)
{
    if (blob_len < KC_LOCAL_NONCE_SIZE + KC_TAG_SIZE) {
        return 0u;
    }
    return blob_len - KC_LOCAL_NONCE_SIZE - KC_TAG_SIZE;
}

kc_status kc_local_seal(const uint8_t *key,
                        size_t key_len,
                        const uint8_t *nonce,
                        size_t nonce_len,
                        const uint8_t *aad,
                        size_t aad_len,
                        const uint8_t *plaintext,
                        size_t plaintext_len,
                        uint8_t *out,
                        size_t out_cap,
                        size_t *out_len)
{
    static const uint8_t empty = 0u;
    size_t required = kc_local_seal_bound(plaintext_len);

    if (key_len != KC_LOCAL_KEY_SIZE) {
        return KC_ERR_BAD_KEY_LENGTH;
    }
    if (key == NULL || nonce == NULL || nonce_len != KC_LOCAL_NONCE_SIZE ||
        (aad == NULL && aad_len != 0u) ||
        (plaintext == NULL && plaintext_len != 0u) || out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (required == 0u || out == NULL || out_cap < required) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    memcpy(out, nonce, KC_LOCAL_NONCE_SIZE);
    crypto_aead_lock(out + KC_LOCAL_NONCE_SIZE,
                     out + KC_LOCAL_NONCE_SIZE + plaintext_len, key, nonce,
                     aad, aad_len, plaintext_len == 0u ? &empty : plaintext,
                     plaintext_len);
    *out_len = required;
    return KC_OK;
}

kc_status kc_local_open(const uint8_t *key,
                        size_t key_len,
                        const uint8_t *aad,
                        size_t aad_len,
                        const uint8_t *blob,
                        size_t blob_len,
                        uint8_t *out,
                        size_t out_cap,
                        size_t *out_len)
{
    uint8_t empty = 0u;
    size_t plaintext_len;
    uint8_t *target;

    if (key_len != KC_LOCAL_KEY_SIZE) {
        return KC_ERR_BAD_KEY_LENGTH;
    }
    if (key == NULL || (aad == NULL && aad_len != 0u) || out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (blob == NULL || blob_len < KC_LOCAL_NONCE_SIZE + KC_TAG_SIZE) {
        return KC_ERR_MALFORMED;
    }
    plaintext_len = kc_local_open_bound(blob_len);
    if (out_cap < plaintext_len || (out == NULL && plaintext_len != 0u)) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    target = plaintext_len == 0u ? &empty : out;
    if (crypto_aead_unlock(target, blob + KC_LOCAL_NONCE_SIZE + plaintext_len,
                           key, blob, aad, aad_len,
                           blob + KC_LOCAL_NONCE_SIZE, plaintext_len) != 0) {
        if (out != NULL && plaintext_len != 0u) {
            crypto_wipe(out, plaintext_len);
        }
        return KC_ERR_WRONG_KEY;
    }
    *out_len = plaintext_len;
    return KC_OK;
}
