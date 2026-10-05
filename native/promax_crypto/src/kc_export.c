#include "kc_internal.h"

#include "kc_codec.h"
#include "kc_session_state.h"
#include "monocypher.h"
#include <stdlib.h>
#include <string.h>

#define KC_EXPORT_VERSION 0x01u
#define KC_EXPORT_SALT_SIZE 16u
#define KC_EXPORT_HEADER_SIZE (1u + KC_EXPORT_SALT_SIZE + 4u + 4u + KC_LOCAL_NONCE_SIZE)
#define KC_EXPORT_MIN_BLOCKS 8u
#define KC_EXPORT_MAX_PASSES 8u
#define KC_EXPORT_MAX_KIB 262144u

static kc_status kc_export_key(const uint8_t *password,
                               size_t password_len,
                               const uint8_t *salt,
                               uint32_t memory_kib,
                               uint32_t passes,
                               uint8_t out_key[32])
{
    crypto_argon2_config config;
    crypto_argon2_inputs inputs;
    void *work_area;
    size_t work_size;

    if (password_len == 0u) {
        return KC_ERR_EMPTY_PASSWORD;
    }
    if (password == NULL || password_len > UINT32_MAX ||
        memory_kib < KC_EXPORT_MIN_BLOCKS || memory_kib > KC_EXPORT_MAX_KIB ||
        passes == 0u || passes > KC_EXPORT_MAX_PASSES) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    work_size = (size_t)memory_kib * 1024u;
    work_area = malloc(work_size);
    if (work_area == NULL) {
        return KC_ERR_OUT_OF_MEMORY;
    }
    config.algorithm = CRYPTO_ARGON2_ID;
    config.nb_blocks = memory_kib;
    config.nb_passes = passes;
    config.nb_lanes = 1u;
    inputs.pass = password;
    inputs.pass_size = (uint32_t)password_len;
    inputs.salt = salt;
    inputs.salt_size = KC_EXPORT_SALT_SIZE;
    crypto_argon2(out_key, 32u, work_area, config, inputs,
                  crypto_argon2_no_extras);
    crypto_wipe(work_area, work_size);
    free(work_area);
    return KC_OK;
}

size_t kc_export_seal_bound(size_t container_len)
{
    size_t result;

    if (!kc_size_add(container_len, KC_EXPORT_HEADER_SIZE + KC_TAG_SIZE,
                     &result)) {
        return 0u;
    }
    return result;
}

size_t kc_export_open_bound(size_t blob_len)
{
    if (blob_len < KC_EXPORT_HEADER_SIZE + KC_TAG_SIZE) {
        return 0u;
    }
    return blob_len - KC_EXPORT_HEADER_SIZE - KC_TAG_SIZE;
}

kc_status kc_export_seal(const uint8_t *password,
                         size_t password_len,
                         uint32_t memory_kib,
                         uint32_t passes,
                         const uint8_t *random,
                         size_t random_len,
                         const uint8_t *container,
                         size_t container_len,
                         uint8_t *out,
                         size_t out_cap,
                         size_t *out_len)
{
    static const uint8_t empty = 0u;
    uint8_t key[32];
    size_t required = kc_export_seal_bound(container_len);
    kc_status status;

    if (random == NULL || random_len != KC_EXPORT_RANDOM_SIZE ||
        (container == NULL && container_len != 0u) || out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (required == 0u || out == NULL || out_cap < required) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_export_key(password, password_len, random, memory_kib, passes,
                           key);
    if (status != KC_OK) {
        return status;
    }
    out[0] = KC_EXPORT_VERSION;
    memcpy(out + 1, random, KC_EXPORT_SALT_SIZE);
    kc_store_u32(out + 1 + KC_EXPORT_SALT_SIZE, memory_kib);
    kc_store_u32(out + 1 + KC_EXPORT_SALT_SIZE + 4, passes);
    memcpy(out + 1 + KC_EXPORT_SALT_SIZE + 8, random + KC_EXPORT_SALT_SIZE,
           KC_LOCAL_NONCE_SIZE);
    crypto_aead_lock(out + KC_EXPORT_HEADER_SIZE,
                     out + KC_EXPORT_HEADER_SIZE + container_len, key,
                     out + 1 + KC_EXPORT_SALT_SIZE + 8, out,
                     KC_EXPORT_HEADER_SIZE,
                     container_len == 0u ? &empty : container, container_len);
    crypto_wipe(key, sizeof(key));
    *out_len = required;
    return KC_OK;
}

static kc_status kc_export_mark_sessions(uint8_t *container,
                                         size_t container_len)
{
    kc_session *session;
    uint32_t count;
    uint32_t index;
    size_t offset = 4u;
    kc_status status = KC_OK;

    if (container_len < 4u) {
        return KC_ERR_MALFORMED;
    }
    count = kc_load_u32(container);
    session = (kc_session *)malloc(sizeof(*session));
    if (session == NULL) {
        return KC_ERR_OUT_OF_MEMORY;
    }
    for (index = 0u; index < count; index++) {
        uint32_t item_len;
        if (container_len - offset < 4u) {
            status = KC_ERR_MALFORMED;
            break;
        }
        item_len = kc_load_u32(container + offset);
        offset += 4u;
        if (container_len - offset < item_len) {
            status = KC_ERR_MALFORMED;
            break;
        }
        if (index != 0u &&
            kc_session_parse(container + offset, item_len, session) == KC_OK) {
            size_t written;
            session->flags |= KC_FLAG_FORCE_DH;
            kc_session_serialize(session, container + offset, item_len,
                                 &written);
            kc_session_wipe(session);
        }
        offset += item_len;
    }
    if (status == KC_OK && offset != container_len) {
        status = KC_ERR_MALFORMED;
    }
    kc_session_wipe(session);
    free(session);
    return status;
}

kc_status kc_export_open(const uint8_t *password,
                         size_t password_len,
                         const uint8_t *blob,
                         size_t blob_len,
                         uint8_t *out_container,
                         size_t out_cap,
                         size_t *out_len)
{
    uint8_t empty = 0u;
    uint8_t key[32];
    size_t container_len;
    uint32_t memory_kib;
    uint32_t passes;
    kc_status status;

    if (out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (blob == NULL || blob_len < KC_EXPORT_HEADER_SIZE + KC_TAG_SIZE) {
        return KC_ERR_MALFORMED;
    }
    if (blob[0] != KC_EXPORT_VERSION) {
        return KC_ERR_UNSUPPORTED_VERSION;
    }
    container_len = kc_export_open_bound(blob_len);
    if (out_cap < container_len || (out_container == NULL && container_len != 0u)) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    memory_kib = kc_load_u32(blob + 1 + KC_EXPORT_SALT_SIZE);
    passes = kc_load_u32(blob + 1 + KC_EXPORT_SALT_SIZE + 4);
    status = kc_export_key(password, password_len, blob + 1, memory_kib, passes,
                           key);
    if (status != KC_OK) {
        return status == KC_ERR_INVALID_ARGUMENT ? KC_ERR_MALFORMED : status;
    }
    if (crypto_aead_unlock(container_len == 0u ? &empty : out_container,
                           blob + KC_EXPORT_HEADER_SIZE + container_len, key,
                           blob + 1 + KC_EXPORT_SALT_SIZE + 8, blob,
                           KC_EXPORT_HEADER_SIZE, blob + KC_EXPORT_HEADER_SIZE,
                           container_len) != 0) {
        crypto_wipe(key, sizeof(key));
        if (out_container != NULL && container_len != 0u) {
            crypto_wipe(out_container, container_len);
        }
        return KC_ERR_WRONG_KEY;
    }
    crypto_wipe(key, sizeof(key));
    status = kc_export_mark_sessions(out_container, container_len);
    if (status != KC_OK) {
        crypto_wipe(out_container, container_len);
        return status;
    }
    *out_len = container_len;
    return KC_OK;
}
