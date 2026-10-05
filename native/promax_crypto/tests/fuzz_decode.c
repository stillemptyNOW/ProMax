#include "promax_crypto.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static uint8_t fuzz_identity_a[KC_IDENTITY_SIZE];
static uint8_t fuzz_identity_b[KC_IDENTITY_SIZE];
static uint8_t fuzz_state_b[KC_SESSION_STATE_MAX];
static size_t fuzz_state_b_len;
static uint8_t fuzz_pending[KC_PENDING_STATE_SIZE];
static size_t fuzz_pending_len;
static int fuzz_ready;

static void fuzz_fill(uint8_t *out, size_t len, uint64_t seed)
{
    uint64_t x = seed;
    size_t index;

    for (index = 0u; index < len; index++) {
        x ^= x >> 12u;
        x ^= x << 25u;
        x ^= x >> 27u;
        out[index] = (uint8_t)((x * 0x2545F4914F6CDD1Dull) >> 56u);
    }
}

static void fuzz_setup(void)
{
    uint8_t seed[KC_SEED_SIZE];
    uint8_t random[KC_OFFER_RANDOM_SIZE];
    uint8_t offer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t answer_text[KC_HANDSHAKE_TEXT_BOUND];
    size_t offer_len = 0u;
    size_t answer_len = 0u;
    size_t len = 0u;

    if (fuzz_ready) {
        return;
    }
    fuzz_fill(seed, sizeof(seed), 1u);
    kc_identity_create(seed, sizeof(seed), fuzz_identity_a,
                       sizeof(fuzz_identity_a), &len);
    fuzz_fill(seed, sizeof(seed), 2u);
    kc_identity_create(seed, sizeof(seed), fuzz_identity_b,
                       sizeof(fuzz_identity_b), &len);
    fuzz_fill(random, KC_OFFER_RANDOM_SIZE, 3u);
    kc_session_offer(fuzz_identity_a, sizeof(fuzz_identity_a), 1, 10, 20,
                     random, KC_OFFER_RANDOM_SIZE, offer_text,
                     sizeof(offer_text), &offer_len, fuzz_pending,
                     sizeof(fuzz_pending), &fuzz_pending_len);
    fuzz_fill(random, KC_ANSWER_RANDOM_SIZE, 4u);
    kc_session_answer(fuzz_identity_b, sizeof(fuzz_identity_b), 1, 20, 10,
                      offer_text, offer_len, NULL, 0u, random,
                      KC_ANSWER_RANDOM_SIZE, answer_text, sizeof(answer_text),
                      &answer_len, fuzz_state_b, sizeof(fuzz_state_b),
                      &fuzz_state_b_len);
    fuzz_ready = 1;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    static const uint8_t key[32] = {7u};
    static const uint8_t nonce12[12] = {1u};
    uint8_t *out;
    uint8_t state_out[KC_SESSION_STATE_MAX];
    uint8_t text_out[4096];
    uint8_t ctx[KC_FILE_CTX_SIZE];
    uint8_t random[KC_OFFER_RANDOM_SIZE] = {0u};
    uint8_t content_type = 0u;
    uint8_t peek_type = 0u;
    uint8_t peek_id[KC_OFFER_ID_SIZE];
    uint8_t peek_public[KC_PUBLIC_KEY_SIZE];
    size_t out_len = 0u;
    size_t state_len = 0u;
    size_t text_len = 0u;
    uint8_t op;

    fuzz_setup();
    if (size == 0u) {
        return 0;
    }
    op = data[0] % 10u;
    data++;
    size--;
    out = (uint8_t *)malloc(size + KC_FILE_CHUNK_SIZE + 64u);
    if (out == NULL) {
        return 0;
    }
    switch (op) {
    case 0:
        kc_classify_text(data, size);
        break;
    case 1:
        kc_decrypt_message(data, size, key, sizeof(key), out, size, &out_len);
        break;
    case 2:
        kc_session_decrypt(fuzz_state_b, fuzz_state_b_len, data, size,
                           &content_type, out, size, &out_len, state_out,
                           sizeof(state_out), &state_len);
        break;
    case 3:
        kc_session_encrypt(data, size, KC_CONTENT_CONTROL, key, 8u, random,
                           KC_ENCRYPT_RANDOM_SIZE, text_out, sizeof(text_out),
                           &text_len, state_out, sizeof(state_out),
                           &state_len);
        break;
    case 4:
        kc_session_answer(fuzz_identity_b, sizeof(fuzz_identity_b), 1, 20, 10,
                          data, size, fuzz_state_b, fuzz_state_b_len, random,
                          KC_ANSWER_RANDOM_SIZE, text_out, sizeof(text_out),
                          &text_len, state_out, sizeof(state_out),
                          &state_len);
        break;
    case 5:
        kc_session_accept(fuzz_identity_a, sizeof(fuzz_identity_a),
                          fuzz_pending, fuzz_pending_len, data, size,
                          fuzz_identity_b + KC_SEED_SIZE, KC_PUBLIC_KEY_SIZE,
                          random, KC_ACCEPT_RANDOM_SIZE, state_out,
                          sizeof(state_out), &state_len);
        break;
    case 6:
        if (kc_file_open_init(ctx, sizeof(ctx), key, sizeof(key), nonce12,
                              sizeof(nonce12)) == KC_OK) {
            kc_file_open_chunk(ctx, sizeof(ctx), data, size, (int)(size & 1u),
                               out, size + KC_FILE_CHUNK_SIZE, &out_len);
        }
        break;
    case 7:
        kc_export_open((const uint8_t *)"pw", 2u, data, size, out, size,
                       &out_len);
        break;
    case 8:
        kc_local_open(key, sizeof(key), NULL, 0u, data, size, out, size,
                      &out_len);
        break;
    default:
        kc_handshake_peek(data, size, &peek_type, peek_id, sizeof(peek_id),
                          peek_public, sizeof(peek_public));
        break;
    }
    free(out);
    return 0;
}
