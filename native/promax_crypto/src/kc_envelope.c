#include "kc_internal.h"

#include "kc_codec.h"
#include "kc_hkdf.h"
#include "kc_ratchet.h"
#include "kc_session_state.h"
#include "monocypher.h"
#include <stdlib.h>
#include <string.h>

#define KC_V3_AAD_SIZE (1u + 8u + 8u + KC_V3_HEADER_SIZE)

static size_t kc_env_round_block(size_t len)
{
    return (len + KC_V3_PAD_BLOCK - 1u) / KC_V3_PAD_BLOCK * KC_V3_PAD_BLOCK;
}

static size_t kc_env_padded_len(size_t body_len)
{
    static const size_t buckets[] = {32u, 64u, 128u, 256u};
    size_t with_marker;
    size_t ceiling;
    size_t index;

    if (!kc_size_add(body_len, 1u, &with_marker)) {
        return 0u;
    }
    for (index = 0u; index < sizeof(buckets) / sizeof(buckets[0]); index++) {
        if (with_marker <= buckets[index]) {
            return buckets[index];
        }
    }
    ceiling = kc_env_round_block(KC_SESSION_PLAINTEXT_MAX + 2u);
    return with_marker <= ceiling ? ceiling : kc_env_round_block(with_marker);
}

static int kc_env_is_shaped(size_t blob_len)
{
    return blob_len >= KC_V3_ENVELOPE_MIN &&
           (blob_len - KC_V3_HEADER_SIZE - KC_TAG_SIZE) % KC_V3_PAD_BLOCK == 0u;
}

static int kc_env_is_handshake(const uint8_t *blob, size_t blob_len)
{
    return blob_len == KC_HANDSHAKE_SIZE && blob[0] == KC_V3_VERSION &&
           (blob[1] == KC_V3_OFFER || blob[1] == KC_V3_ANSWER);
}

static void kc_env_aad(uint8_t out[KC_V3_AAD_SIZE],
                       int64_t chat_id,
                       int64_t sender_id,
                       const uint8_t repr[32],
                       const uint8_t counters[8])
{
    out[0] = KC_V3_VERSION;
    kc_store_i64(out + 1, chat_id);
    kc_store_i64(out + 9, sender_id);
    memcpy(out + 17, repr, 32u);
    memcpy(out + 49, counters, 8u);
}

static void kc_env_mask(const uint8_t ok[32],
                        const uint8_t repr[32],
                        const uint8_t tag[KC_TAG_SIZE],
                        uint8_t out[8])
{
    uint8_t input[32u + KC_TAG_SIZE];

    memcpy(input, repr, 32u);
    memcpy(input + 32u, tag, KC_TAG_SIZE);
    crypto_blake2b_keyed(out, 8u, ok, 32u, input, sizeof(input));
}

static int kc_env_content_valid(uint8_t content_type)
{
    return content_type == KC_CONTENT_TEXT || content_type == KC_CONTENT_FILE ||
           content_type == KC_CONTENT_CONTROL;
}

size_t kc_session_encrypt_bound(size_t plaintext_len)
{
    size_t padded;
    size_t blob_len;

    if (plaintext_len > KC_SESSION_PLAINTEXT_MAX) {
        return 0u;
    }
    padded = kc_env_padded_len(plaintext_len + 1u);
    if (padded == 0u ||
        !kc_size_add(padded, KC_V3_HEADER_SIZE + KC_TAG_SIZE, &blob_len)) {
        return 0u;
    }
    return kc_alphabet_encode_bound(blob_len);
}

kc_status kc_session_encrypt(const uint8_t *state,
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
                             size_t *state_out_len)
{
    kc_session *session;
    uint8_t mk[32];
    uint8_t key[32];
    uint8_t nonce[12];
    uint8_t mask[8];
    uint8_t counters[8];
    uint8_t aad[KC_V3_AAD_SIZE];
    uint8_t *blob;
    size_t padded;
    size_t blob_len;
    size_t sealed_len;
    size_t required;
    uint32_t n;
    uint32_t pn;
    kc_status status;

    if (!kc_env_content_valid(content_type) ||
        (plaintext == NULL && plaintext_len != 0u) || random == NULL ||
        random_len != KC_ENCRYPT_RANDOM_SIZE || text_len == NULL ||
        state_out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (plaintext_len > KC_SESSION_PLAINTEXT_MAX) {
        return KC_ERR_TOO_LONG;
    }
    if (content_type == KC_CONTENT_TEXT &&
        !kc_utf8_valid(plaintext, plaintext_len)) {
        return KC_ERR_MALFORMED;
    }
    required = kc_session_encrypt_bound(plaintext_len);
    if (required == 0u || out_text == NULL || text_cap < required ||
        out_state == NULL || state_cap < KC_SESSION_FIXED_SIZE) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    session = (kc_session *)malloc(sizeof(*session));
    if (session == NULL) {
        return KC_ERR_OUT_OF_MEMORY;
    }
    status = kc_session_parse(state, state_len, session);
    if (status != KC_OK) {
        free(session);
        return status;
    }
    padded = kc_env_padded_len(plaintext_len + 1u);
    blob_len = KC_V3_HEADER_SIZE + padded + KC_TAG_SIZE;
    blob = (uint8_t *)malloc(blob_len);
    if (blob == NULL) {
        kc_session_wipe(session);
        free(session);
        return KC_ERR_OUT_OF_MEMORY;
    }
    status = kc_ratchet_next_send_key(session, random, mk, &n, &pn, blob);
    if (status == KC_OK) {
        uint8_t *body = blob + KC_V3_HEADER_SIZE;
        kc_store_u32(counters, pn);
        kc_store_u32(counters + 4, n);
        memset(body, 0, padded);
        body[0] = content_type;
        if (plaintext_len != 0u) {
            memcpy(body + 1, plaintext, plaintext_len);
        }
        body[1u + plaintext_len] = 0x80u;
        kc_env_aad(aad, session->chat_id, session->my_id, blob, counters);
        kc_kdf_message(mk, key, nonce);
        status = kc_seal(body, padded, key, sizeof(key), nonce, sizeof(nonce),
                         aad, sizeof(aad), body, padded + KC_TAG_SIZE,
                         &sealed_len);
        if (status == KC_OK) {
            kc_env_mask(session->ok, blob, blob + blob_len - KC_TAG_SIZE, mask);
            for (n = 0u; n < 8u; n++) {
                blob[32u + n] = counters[n] ^ mask[n];
            }
        }
    }
    if (status == KC_OK) {
        status = kc_alphabet_encode(blob, blob_len, out_text, text_cap,
                                    text_len);
    }
    if (status == KC_OK) {
        status = kc_session_serialize(session, out_state, state_cap,
                                      state_out_len);
    }
    crypto_wipe(mk, sizeof(mk));
    crypto_wipe(key, sizeof(key));
    crypto_wipe(nonce, sizeof(nonce));
    crypto_wipe(blob, blob_len);
    free(blob);
    kc_session_wipe(session);
    free(session);
    return status;
}

size_t kc_session_decrypt_bound(size_t text_len)
{
    return text_len;
}

kc_status kc_session_decrypt(const uint8_t *state,
                             size_t state_len,
                             const uint8_t *text,
                             size_t text_len,
                             uint8_t *out_content_type,
                             uint8_t *out_plaintext,
                             size_t plaintext_cap,
                             size_t *plaintext_len,
                             uint8_t *out_state,
                             size_t state_cap,
                             size_t *state_out_len)
{
    kc_session *session = NULL;
    uint8_t *blob = NULL;
    uint8_t *body = NULL;
    size_t blob_len = 0u;
    size_t body_len;
    size_t opened_len;
    size_t content_len = 0u;
    uint8_t mk[32];
    uint8_t key[32];
    uint8_t nonce[12];
    uint8_t mask[8];
    uint8_t counters[8];
    uint8_t aad[KC_V3_AAD_SIZE];
    uint32_t pn;
    uint32_t n;
    size_t index;
    kc_status status;

    if (out_content_type == NULL || plaintext_len == NULL ||
        state_out_len == NULL || (out_plaintext == NULL && plaintext_cap != 0u)) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    status = kc_alphabet_decode(text, text_len, &blob, &blob_len);
    if (status == KC_ERR_OUT_OF_MEMORY) {
        return status;
    }
    if (status != KC_OK) {
        uint8_t handshake[KC_HANDSHAKE_SIZE];
        return kc_handshake_decode(text, text_len, handshake) == KC_OK
                   ? KC_ERR_HANDSHAKE_MESSAGE
                   : KC_ERR_NOT_ENCRYPTED;
    }
    if (kc_env_is_handshake(blob, blob_len)) {
        free(blob);
        return KC_ERR_HANDSHAKE_MESSAGE;
    }
    if (!kc_env_is_shaped(blob_len)) {
        free(blob);
        return KC_ERR_NOT_ENCRYPTED;
    }
    body_len = blob_len - KC_V3_HEADER_SIZE - KC_TAG_SIZE;
    if (plaintext_cap < body_len || out_state == NULL ||
        state_cap < KC_SESSION_FIXED_SIZE) {
        free(blob);
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    session = (kc_session *)malloc(sizeof(*session));
    body = (uint8_t *)malloc(body_len);
    if (session == NULL || body == NULL) {
        free(session);
        free(body);
        free(blob);
        return KC_ERR_OUT_OF_MEMORY;
    }
    status = kc_session_parse(state, state_len, session);
    if (status == KC_OK) {
        kc_env_mask(session->ok, blob, blob + blob_len - KC_TAG_SIZE, mask);
        for (index = 0u; index < 8u; index++) {
            counters[index] = blob[32u + index] ^ mask[index];
        }
        pn = kc_load_u32(counters);
        n = kc_load_u32(counters + 4);
        status = kc_ratchet_receive_key(session, blob, pn, n, mk);
    }
    if (status == KC_OK) {
        kc_env_aad(aad, session->chat_id, session->peer_id, blob, counters);
        kc_kdf_message(mk, key, nonce);
        status = kc_open(blob + KC_V3_HEADER_SIZE, body_len + KC_TAG_SIZE, key,
                         sizeof(key), nonce, aad, sizeof(aad), body, body_len,
                         &opened_len);
        crypto_wipe(mk, sizeof(mk));
        crypto_wipe(key, sizeof(key));
        crypto_wipe(nonce, sizeof(nonce));
    }
    if (status == KC_OK) {
        content_len = body_len;
        while (content_len > 0u && body[content_len - 1u] == 0x00u) {
            content_len--;
        }
        if (content_len < 2u || body[content_len - 1u] != 0x80u ||
            !kc_env_content_valid(body[0])) {
            status = KC_ERR_MALFORMED;
        } else {
            content_len -= 2u;
            if (body[0] == KC_CONTENT_TEXT &&
                !kc_utf8_valid(body + 1, content_len)) {
                status = KC_ERR_MALFORMED;
            }
        }
    }
    if (status == KC_OK) {
        status = kc_session_serialize(session, out_state, state_cap,
                                      state_out_len);
    }
    if (status == KC_OK) {
        *out_content_type = body[0];
        if (content_len != 0u) {
            memcpy(out_plaintext, body + 1, content_len);
        }
        *plaintext_len = content_len;
    }
    crypto_wipe(body, body_len);
    free(body);
    crypto_wipe(blob, blob_len);
    free(blob);
    kc_session_wipe(session);
    free(session);
    return status;
}

kc_status kc_session_peer_public_key(const uint8_t *state,
                                     size_t state_len,
                                     uint8_t *out_public,
                                     size_t out_cap,
                                     size_t *out_len)
{
    if (out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (state == NULL || state_len < KC_SESSION_FIXED_SIZE ||
        state[0] != KC_SESSION_FMT) {
        return KC_ERR_BAD_STATE;
    }
    if (out_public == NULL || out_cap < KC_PUBLIC_KEY_SIZE) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    memcpy(out_public, state + 2u + 24u + KC_OFFER_ID_SIZE, KC_PUBLIC_KEY_SIZE);
    *out_len = KC_PUBLIC_KEY_SIZE;
    return KC_OK;
}

static const uint8_t *kc_env_last_line(const uint8_t *text,
                                       size_t text_len,
                                       size_t *out_len)
{
    size_t index = text_len;

    while (index > 0u) {
        if (text[index - 1u] == (uint8_t)'\n') {
            *out_len = text_len - index;
            return text + index;
        }
        index--;
    }
    return NULL;
}

kc_status kc_handshake_decode(const uint8_t *text,
                              size_t text_len,
                              uint8_t out[KC_HANDSHAKE_SIZE])
{
    uint8_t *blob = NULL;
    size_t blob_len = 0u;
    const uint8_t *line;
    size_t line_len = 0u;
    kc_status status;

    if (text == NULL && text_len != 0u) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    status = kc_alphabet_decode(text, text_len, &blob, &blob_len);
    if (status != KC_OK || blob_len != KC_HANDSHAKE_SIZE) {
        free(blob);
        blob = NULL;
        line = kc_env_last_line(text, text_len, &line_len);
        if (line == NULL) {
            return KC_ERR_MALFORMED;
        }
        status = kc_alphabet_decode(line, line_len, &blob, &blob_len);
        if (status != KC_OK) {
            return status == KC_ERR_OUT_OF_MEMORY ? status : KC_ERR_MALFORMED;
        }
    }
    if (blob_len != KC_HANDSHAKE_SIZE) {
        free(blob);
        return KC_ERR_MALFORMED;
    }
    if (blob[0] != KC_V3_VERSION) {
        free(blob);
        return KC_ERR_UNSUPPORTED_VERSION;
    }
    if (blob[1] != KC_V3_OFFER && blob[1] != KC_V3_ANSWER) {
        free(blob);
        return KC_ERR_MALFORMED;
    }
    memcpy(out, blob, KC_HANDSHAKE_SIZE);
    free(blob);
    return KC_OK;
}

int kc_classify_text(const uint8_t *text, size_t text_len)
{
    uint8_t *blob = NULL;
    size_t blob_len = 0u;
    uint8_t handshake[KC_HANDSHAKE_SIZE];
    int result = KC_TEXT_NONE;

    if (kc_alphabet_decode(text, text_len, &blob, &blob_len) == KC_OK) {
        if (kc_env_is_handshake(blob, blob_len)) {
            result = blob[1] == KC_V3_OFFER ? KC_TEXT_OFFER : KC_TEXT_ANSWER;
        } else if (blob_len >= KC_MESSAGE_HEADER_SIZE + KC_NONCE_SIZE +
                                   KC_TAG_SIZE &&
                   blob[0] == KC_MAGIC && blob[1] == KC_MESSAGE_VERSION) {
            result = KC_TEXT_LEGACY;
        } else if (kc_env_is_shaped(blob_len)) {
            result = KC_TEXT_SESSION;
        }
        free(blob);
        return result;
    }
    if (kc_handshake_decode(text, text_len, handshake) == KC_OK) {
        return handshake[1] == KC_V3_OFFER ? KC_TEXT_OFFER : KC_TEXT_ANSWER;
    }
    return KC_TEXT_NONE;
}
