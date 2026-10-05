#include "kc_internal.h"
#include "kc_sha256.h"

#include "monocypher.h"
#include <stdlib.h>
#include <string.h>

static const uint8_t kc_salt_context[] = "promax-enc-v1";
static const size_t kc_argon_work_size = 65536u * 1024u;

static kc_status kc_validate_key(const uint8_t *key, size_t key_len)
{
    if (key_len != KC_KEY_SIZE) {
        return KC_ERR_BAD_KEY_LENGTH;
    }
    if (key == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    return KC_OK;
}

static const uint8_t *kc_nonnull_input(const uint8_t *input,
                                       size_t input_len,
                                       const uint8_t *fallback)
{
    return input_len == 0u ? fallback : input;
}

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
                         size_t *out_len)
{
    static const uint8_t empty = 0u;
    crypto_aead_ctx context;
    size_t required;
    kc_status status;

    status = kc_validate_key(key, key_len);
    if (status != KC_OK) {
        return status;
    }
    if ((plaintext == NULL && plaintext_len != 0u) || nonce == NULL ||
        nonce_len != KC_NONCE_SIZE || header == NULL || out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (!kc_size_add(plaintext_len, KC_TAG_SIZE, &required) ||
        out_cap < required || (out == NULL && required != 0u)) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    crypto_aead_init_ietf(&context, key, nonce);
    crypto_aead_write(&context, out, out + plaintext_len, header, header_len,
                      kc_nonnull_input(plaintext, plaintext_len, &empty),
                      plaintext_len);
    crypto_wipe(&context, sizeof(context));
    *out_len = required;
    return KC_OK;
}

kc_status kc_open(const uint8_t *sealed,
                         size_t sealed_len,
                         const uint8_t *key,
                         size_t key_len,
                         const uint8_t *nonce,
                         const uint8_t *header,
                         size_t header_len,
                         uint8_t *out,
                         size_t out_cap,
                         size_t *out_len)
{
    uint8_t empty = 0u;
    crypto_aead_ctx context;
    size_t required;
    uint8_t *target;
    kc_status status;

    status = kc_validate_key(key, key_len);
    if (status != KC_OK) {
        return status;
    }
    if (sealed == NULL || nonce == NULL || header == NULL || out_len == NULL ||
        sealed_len < KC_TAG_SIZE) {
        return KC_ERR_MALFORMED;
    }
    required = sealed_len - KC_TAG_SIZE;
    if (out_cap < required || (out == NULL && required != 0u)) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    target = required == 0u ? &empty : out;
    crypto_aead_init_ietf(&context, key, nonce);
    if (crypto_aead_read(&context, target, sealed + required, header,
                         header_len, sealed, required) != 0) {
        crypto_wipe(&context, sizeof(context));
        if (out != NULL && required != 0u) {
            crypto_wipe(out, required);
        }
        return KC_ERR_WRONG_KEY;
    }
    crypto_wipe(&context, sizeof(context));
    *out_len = required;
    return KC_OK;
}

kc_status kc_derive_key(const uint8_t *password,
                        size_t password_len,
                        uint8_t *out_key,
                        size_t out_key_len)
{
    kc_sha256 hash;
    crypto_argon2_config config;
    crypto_argon2_inputs inputs;
    uint8_t digest[KC_SHA256_SIZE];
    void *work_area;

    if (password_len == 0u) {
        return KC_ERR_EMPTY_PASSWORD;
    }
    if (password == NULL || out_key == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_key_len != KC_KEY_SIZE) {
        return KC_ERR_BAD_KEY_LENGTH;
    }
    if (password_len > UINT32_MAX) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    kc_sha256_init(&hash);
    kc_sha256_update(&hash, kc_salt_context, sizeof(kc_salt_context) - 1u);
    kc_sha256_update(&hash, password, password_len);
    kc_sha256_final(&hash, digest);
    work_area = malloc(kc_argon_work_size);
    if (work_area == NULL) {
        crypto_wipe(digest, sizeof(digest));
        return KC_ERR_OUT_OF_MEMORY;
    }
    config.algorithm = CRYPTO_ARGON2_ID;
    config.nb_blocks = 65536u;
    config.nb_passes = 3u;
    config.nb_lanes = 1u;
    inputs.pass = password;
    inputs.salt = digest;
    inputs.pass_size = (uint32_t)password_len;
    inputs.salt_size = 16u;
    crypto_argon2(out_key, KC_KEY_SIZE, work_area, config, inputs,
                  crypto_argon2_no_extras);
    crypto_wipe(work_area, kc_argon_work_size);
    free(work_area);
    crypto_wipe(digest, sizeof(digest));
    return KC_OK;
}

size_t kc_encrypt_message_bound(size_t plaintext_len)
{
    size_t blob_len;

    if (!kc_size_add(plaintext_len,
                     KC_MESSAGE_HEADER_SIZE + KC_NONCE_SIZE + KC_TAG_SIZE,
                     &blob_len)) {
        return 0u;
    }
    return kc_alphabet_encode_bound(blob_len);
}

kc_status kc_encrypt_message(const uint8_t *plaintext,
                             size_t plaintext_len,
                             const uint8_t *key,
                             size_t key_len,
                             const uint8_t *nonce,
                             size_t nonce_len,
                             uint8_t *out,
                             size_t out_cap,
                             size_t *out_len)
{
    uint8_t header[KC_MESSAGE_HEADER_SIZE] = {KC_MAGIC, KC_MESSAGE_VERSION};
    uint8_t *blob;
    size_t blob_len;
    size_t sealed_len;
    size_t required;
    kc_status status;

    if (!kc_utf8_valid(plaintext, plaintext_len)) {
        return KC_ERR_MALFORMED;
    }
    required = kc_encrypt_message_bound(plaintext_len);
    if (required == 0u || out_cap < required || out == NULL ||
        out_len == NULL) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    if (!kc_size_add(plaintext_len,
                     KC_MESSAGE_HEADER_SIZE + KC_NONCE_SIZE + KC_TAG_SIZE,
                     &blob_len)) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    blob = (uint8_t *)malloc(blob_len);
    if (blob == NULL) {
        return KC_ERR_OUT_OF_MEMORY;
    }
    memcpy(blob, header, KC_MESSAGE_HEADER_SIZE);
    if (nonce != NULL && nonce_len == KC_NONCE_SIZE) {
        memcpy(blob + KC_MESSAGE_HEADER_SIZE, nonce, KC_NONCE_SIZE);
    }
    status = kc_seal(plaintext, plaintext_len, key, key_len, nonce, nonce_len,
                     header, KC_MESSAGE_HEADER_SIZE,
                     blob + KC_MESSAGE_HEADER_SIZE + KC_NONCE_SIZE,
                     blob_len - KC_MESSAGE_HEADER_SIZE - KC_NONCE_SIZE,
                     &sealed_len);
    if (status == KC_OK) {
        status = kc_alphabet_encode(blob, blob_len, out, out_cap, out_len);
    }
    crypto_wipe(blob, blob_len);
    free(blob);
    return status;
}

size_t kc_decrypt_message_bound(size_t text_len)
{
    return text_len;
}

kc_status kc_decrypt_message(const uint8_t *text,
                             size_t text_len,
                             const uint8_t *key,
                             size_t key_len,
                             uint8_t *out,
                             size_t out_cap,
                             size_t *out_len)
{
    uint8_t *blob = NULL;
    size_t blob_len = 0u;
    size_t plaintext_len;
    kc_status status;

    status = kc_alphabet_decode(text, text_len, &blob, &blob_len);
    if (status != KC_OK) {
        return status;
    }
    if (blob_len < KC_MESSAGE_HEADER_SIZE + KC_NONCE_SIZE + KC_TAG_SIZE ||
        blob[0] != KC_MAGIC || blob[1] != KC_MESSAGE_VERSION) {
        free(blob);
        return KC_ERR_NOT_ENCRYPTED;
    }
    plaintext_len =
        blob_len - KC_MESSAGE_HEADER_SIZE - KC_NONCE_SIZE - KC_TAG_SIZE;
    if (out_cap < plaintext_len || (out == NULL && plaintext_len != 0u) ||
        out_len == NULL) {
        free(blob);
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_open(blob + KC_MESSAGE_HEADER_SIZE + KC_NONCE_SIZE,
                     blob_len - KC_MESSAGE_HEADER_SIZE - KC_NONCE_SIZE, key,
                     key_len, blob + KC_MESSAGE_HEADER_SIZE, blob,
                     KC_MESSAGE_HEADER_SIZE, out, out_cap, out_len);
    crypto_wipe(blob, blob_len);
    free(blob);
    if (status == KC_OK && !kc_utf8_valid(out, *out_len)) {
        crypto_wipe(out, *out_len);
        return KC_ERR_MALFORMED;
    }
    return status;
}

int kc_looks_encrypted_message(const uint8_t *text, size_t text_len)
{
    uint8_t *blob = NULL;
    size_t blob_len = 0u;
    kc_status status;
    int result;

    status = kc_alphabet_decode(text, text_len, &blob, &blob_len);
    if (status != KC_OK) {
        return 0;
    }
    result = blob_len >=
                 KC_MESSAGE_HEADER_SIZE + KC_NONCE_SIZE + KC_TAG_SIZE &&
             blob[0] == KC_MAGIC && blob[1] == KC_MESSAGE_VERSION;
    free(blob);
    return result;
}

size_t kc_encrypt_image_blob_bound(size_t plaintext_len)
{
    size_t result;

    if (!kc_size_add(plaintext_len,
                     KC_IMAGE_HEADER_SIZE + KC_NONCE_SIZE + KC_TAG_SIZE,
                     &result) ||
        result - KC_IMAGE_HEADER_SIZE > UINT32_MAX) {
        return 0u;
    }
    return result;
}

kc_status kc_encrypt_image_blob(const uint8_t *plaintext,
                                size_t plaintext_len,
                                const uint8_t *key,
                                size_t key_len,
                                const uint8_t *nonce,
                                size_t nonce_len,
                                uint8_t *out,
                                size_t out_cap,
                                size_t *out_len)
{
    uint8_t header[KC_IMAGE_HEADER_SIZE];
    size_t required = kc_encrypt_image_blob_bound(plaintext_len);
    size_t payload_len;
    size_t sealed_len;
    kc_status status;

    if (required == 0u || out == NULL || out_len == NULL ||
        out_cap < required) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    payload_len = required - KC_IMAGE_HEADER_SIZE;
    header[0] = KC_MAGIC;
    header[1] = KC_IMAGE_VERSION;
    header[2] = (uint8_t)(payload_len >> 24u);
    header[3] = (uint8_t)(payload_len >> 16u);
    header[4] = (uint8_t)(payload_len >> 8u);
    header[5] = (uint8_t)payload_len;
    memcpy(out, header, KC_IMAGE_HEADER_SIZE);
    if (nonce != NULL && nonce_len == KC_NONCE_SIZE) {
        memcpy(out + KC_IMAGE_HEADER_SIZE, nonce, KC_NONCE_SIZE);
    }
    status = kc_seal(plaintext, plaintext_len, key, key_len, nonce, nonce_len,
                     header, KC_IMAGE_HEADER_SIZE,
                     out + KC_IMAGE_HEADER_SIZE + KC_NONCE_SIZE,
                     out_cap - KC_IMAGE_HEADER_SIZE - KC_NONCE_SIZE,
                     &sealed_len);
    if (status != KC_OK) {
        crypto_wipe(out, required);
        return status;
    }
    *out_len = required;
    return KC_OK;
}

static int kc_image_payload_len(const uint8_t *blob,
                                size_t blob_len,
                                size_t *payload_len)
{
    uint32_t encoded;

    if (blob == NULL || payload_len == NULL || blob_len < KC_IMAGE_HEADER_SIZE ||
        blob[0] != KC_MAGIC || blob[1] != KC_IMAGE_VERSION) {
        return 0;
    }
    encoded = ((uint32_t)blob[2] << 24u) | ((uint32_t)blob[3] << 16u) |
              ((uint32_t)blob[4] << 8u) | (uint32_t)blob[5];
    if (encoded < KC_NONCE_SIZE + KC_TAG_SIZE ||
        (size_t)encoded > blob_len - KC_IMAGE_HEADER_SIZE) {
        return 0;
    }
    *payload_len = encoded;
    return 1;
}

size_t kc_decrypt_image_blob_bound(size_t blob_len)
{
    if (blob_len < KC_IMAGE_HEADER_SIZE + KC_NONCE_SIZE + KC_TAG_SIZE) {
        return 0u;
    }
    return blob_len - KC_IMAGE_HEADER_SIZE - KC_NONCE_SIZE - KC_TAG_SIZE;
}

kc_status kc_decrypt_image_blob(const uint8_t *blob,
                                size_t blob_len,
                                const uint8_t *key,
                                size_t key_len,
                                uint8_t *out,
                                size_t out_cap,
                                size_t *out_len)
{
    size_t payload_len;
    size_t plaintext_len;

    if (!kc_image_payload_len(blob, blob_len, &payload_len)) {
        return KC_ERR_NOT_ENCRYPTED;
    }
    plaintext_len = payload_len - KC_NONCE_SIZE - KC_TAG_SIZE;
    if (out_cap < plaintext_len || (out == NULL && plaintext_len != 0u) ||
        out_len == NULL) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    return kc_open(blob + KC_IMAGE_HEADER_SIZE + KC_NONCE_SIZE,
                   payload_len - KC_NONCE_SIZE, key, key_len,
                   blob + KC_IMAGE_HEADER_SIZE, blob, KC_IMAGE_HEADER_SIZE,
                   out, out_cap, out_len);
}

int kc_looks_encrypted_image_blob(const uint8_t *blob, size_t blob_len)
{
    size_t payload_len;
    return kc_image_payload_len(blob, blob_len, &payload_len);
}
