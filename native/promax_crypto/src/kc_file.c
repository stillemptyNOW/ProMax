#include "kc_internal.h"

#include "kc_codec.h"
#include "monocypher.h"
#include <string.h>

#define KC_FILE_MODE_SEAL 1u
#define KC_FILE_MODE_OPEN 2u
#define KC_FILE_STATE_SIZE 54u
#define KC_FILE_AD_SIZE 18u

static const uint8_t kc_file_label[] = "promax-v3/file";

typedef struct {
    crypto_aead_ctx aead;
    uint32_t index;
    uint8_t finished;
    uint8_t mode;
} kc_file_state;

static void kc_file_store(const kc_file_state *state, uint8_t *ctx)
{
    kc_store_u64(ctx, state->aead.counter);
    memcpy(ctx + 8, state->aead.key, 32u);
    memcpy(ctx + 40, state->aead.nonce, 8u);
    kc_store_u32(ctx + 48, state->index);
    ctx[52] = state->finished;
    ctx[53] = state->mode;
}

static kc_status kc_file_load(kc_file_state *state,
                              const uint8_t *ctx,
                              size_t ctx_len,
                              uint8_t mode)
{
    if (ctx == NULL || ctx_len < KC_FILE_CTX_SIZE) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (ctx[53] != mode) {
        return KC_ERR_BAD_STATE;
    }
    state->aead.counter = kc_load_u64(ctx);
    memcpy(state->aead.key, ctx + 8, 32u);
    memcpy(state->aead.nonce, ctx + 40, 8u);
    state->index = kc_load_u32(ctx + 48);
    state->finished = ctx[52];
    state->mode = ctx[53];
    return state->finished ? KC_ERR_BAD_STATE : KC_OK;
}

static kc_status kc_file_init(uint8_t *ctx,
                              size_t ctx_len,
                              const uint8_t *key,
                              size_t key_len,
                              const uint8_t *nonce,
                              size_t nonce_len,
                              uint8_t mode)
{
    kc_file_state state;

    if (key_len != KC_FILE_KEY_SIZE) {
        return KC_ERR_BAD_KEY_LENGTH;
    }
    if (ctx == NULL || ctx_len < KC_FILE_CTX_SIZE || key == NULL ||
        nonce == NULL || nonce_len != KC_FILE_NONCE_SIZE) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    crypto_aead_init_ietf(&state.aead, key, nonce);
    state.index = 0u;
    state.finished = 0u;
    state.mode = mode;
    memset(ctx, 0, ctx_len);
    kc_file_store(&state, ctx);
    crypto_wipe(&state, sizeof(state));
    return KC_OK;
}

static void kc_file_ad(uint8_t out[KC_FILE_AD_SIZE], uint32_t index, int last)
{
    memcpy(out, kc_file_label, sizeof(kc_file_label) - 1u);
    kc_store_u32(out + sizeof(kc_file_label) - 1u, index);
    out[KC_FILE_AD_SIZE - 1u] = last ? 1u : 0u;
}

size_t kc_file_seal_bound(size_t plaintext_len)
{
    size_t chunks = plaintext_len / KC_FILE_CHUNK_SIZE + 1u;
    size_t overhead;

    if (chunks > SIZE_MAX / KC_TAG_SIZE) {
        return 0u;
    }
    overhead = chunks * KC_TAG_SIZE;
    if (plaintext_len > SIZE_MAX - overhead) {
        return 0u;
    }
    return plaintext_len + overhead;
}

size_t kc_file_open_bound(size_t ciphertext_len)
{
    return ciphertext_len;
}

kc_status kc_file_seal_init(uint8_t *ctx,
                            size_t ctx_len,
                            const uint8_t *key,
                            size_t key_len,
                            const uint8_t *nonce,
                            size_t nonce_len)
{
    return kc_file_init(ctx, ctx_len, key, key_len, nonce, nonce_len,
                        KC_FILE_MODE_SEAL);
}

kc_status kc_file_open_init(uint8_t *ctx,
                            size_t ctx_len,
                            const uint8_t *key,
                            size_t key_len,
                            const uint8_t *nonce,
                            size_t nonce_len)
{
    return kc_file_init(ctx, ctx_len, key, key_len, nonce, nonce_len,
                        KC_FILE_MODE_OPEN);
}

kc_status kc_file_seal_chunk(uint8_t *ctx,
                             size_t ctx_len,
                             const uint8_t *plaintext,
                             size_t plaintext_len,
                             int last,
                             uint8_t *out,
                             size_t out_cap,
                             size_t *out_len)
{
    static const uint8_t empty = 0u;
    kc_file_state state;
    uint8_t ad[KC_FILE_AD_SIZE];
    kc_status status;

    status = kc_file_load(&state, ctx, ctx_len, KC_FILE_MODE_SEAL);
    if (status != KC_OK) {
        return status;
    }
    if ((plaintext == NULL && plaintext_len != 0u) || out_len == NULL ||
        plaintext_len > KC_FILE_CHUNK_SIZE ||
        (!last && plaintext_len != KC_FILE_CHUNK_SIZE)) {
        crypto_wipe(&state, sizeof(state));
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out == NULL || out_cap < plaintext_len + KC_TAG_SIZE) {
        crypto_wipe(&state, sizeof(state));
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    kc_file_ad(ad, state.index, last);
    crypto_aead_write(&state.aead, out, out + plaintext_len, ad, sizeof(ad),
                      plaintext_len == 0u ? &empty : plaintext, plaintext_len);
    state.index++;
    state.finished = last ? 1u : 0u;
    kc_file_store(&state, ctx);
    crypto_wipe(&state, sizeof(state));
    *out_len = plaintext_len + KC_TAG_SIZE;
    return KC_OK;
}

kc_status kc_file_open_chunk(uint8_t *ctx,
                             size_t ctx_len,
                             const uint8_t *chunk,
                             size_t chunk_len,
                             int last,
                             uint8_t *out,
                             size_t out_cap,
                             size_t *out_len)
{
    uint8_t empty = 0u;
    kc_file_state state;
    uint8_t ad[KC_FILE_AD_SIZE];
    size_t plaintext_len;
    kc_status status;

    status = kc_file_load(&state, ctx, ctx_len, KC_FILE_MODE_OPEN);
    if (status != KC_OK) {
        return status;
    }
    if (out_len == NULL) {
        crypto_wipe(&state, sizeof(state));
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (chunk == NULL || chunk_len < KC_TAG_SIZE ||
        chunk_len > KC_FILE_CHUNK_SIZE + KC_TAG_SIZE ||
        (!last && chunk_len != KC_FILE_CHUNK_SIZE + KC_TAG_SIZE)) {
        crypto_wipe(&state, sizeof(state));
        return KC_ERR_MALFORMED;
    }
    plaintext_len = chunk_len - KC_TAG_SIZE;
    if (out_cap < plaintext_len || (out == NULL && plaintext_len != 0u)) {
        crypto_wipe(&state, sizeof(state));
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    kc_file_ad(ad, state.index, last);
    if (crypto_aead_read(&state.aead, plaintext_len == 0u ? &empty : out,
                         chunk + plaintext_len, ad, sizeof(ad), chunk,
                         plaintext_len) != 0) {
        crypto_wipe(&state, sizeof(state));
        if (out != NULL && plaintext_len != 0u) {
            crypto_wipe(out, plaintext_len);
        }
        return KC_ERR_WRONG_KEY;
    }
    state.index++;
    state.finished = last ? 1u : 0u;
    kc_file_store(&state, ctx);
    crypto_wipe(&state, sizeof(state));
    *out_len = plaintext_len;
    return KC_OK;
}
