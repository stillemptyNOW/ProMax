#include "kc_internal.h"

#include "kc_codec.h"
#include "kc_hkdf.h"
#include "kc_identity.h"
#include "kc_ratchet.h"
#include "kc_session_state.h"
#include "monocypher.h"
#include <stdlib.h>
#include <string.h>

#define KC_HS_UNSIGNED 74u
#define KC_HS_OFFSET_ID 2u
#define KC_HS_OFFSET_IK 10u
#define KC_HS_OFFSET_EK 42u
#define KC_HS_OFFSET_SIG 74u
#define KC_HS_SIGN_MAX (16u + 24u + KC_HS_UNSIGNED + 32u)
#define KC_HS_PENDING_OFFSET_EK 33u
#define KC_HS_PENDING_OFFSET_OFFER 65u

static const uint8_t kc_hs_offer_label[] = "promax-v3/offer";
static const uint8_t kc_hs_answer_label[] = "promax-v3/answer";
static const uint8_t kc_hs_sk_label[] = "promax-v3/sk";

static size_t kc_hs_sign_message(uint8_t *out,
                                 const uint8_t *label,
                                 size_t label_len,
                                 int64_t chat_id,
                                 int64_t from_id,
                                 int64_t to_id,
                                 const uint8_t *handshake,
                                 const uint8_t *offer_hash)
{
    size_t offset = 0u;

    memcpy(out, label, label_len);
    offset += label_len;
    kc_store_i64(out + offset, chat_id);
    offset += 8u;
    kc_store_i64(out + offset, from_id);
    offset += 8u;
    kc_store_i64(out + offset, to_id);
    offset += 8u;
    memcpy(out + offset, handshake, KC_HS_UNSIGNED);
    offset += KC_HS_UNSIGNED;
    if (offer_hash != NULL) {
        memcpy(out + offset, offer_hash, 32u);
        offset += 32u;
    }
    return offset;
}

static void kc_hs_offer_hash(const uint8_t *offer, uint8_t out[32])
{
    crypto_blake2b(out, 32u, offer, KC_HANDSHAKE_SIZE);
}

static void kc_hs_secret(const uint8_t dh1[32],
                         const uint8_t dh2[32],
                         const uint8_t dh3[32],
                         const uint8_t *offer,
                         const uint8_t *answer,
                         uint8_t out[96])
{
    uint8_t ikm[128];
    uint8_t info[sizeof(kc_hs_sk_label) - 1u + 32u];
    crypto_blake2b_ctx ctx;

    memset(ikm, 0xFF, 32u);
    memcpy(ikm + 32, dh1, 32u);
    memcpy(ikm + 64, dh2, 32u);
    memcpy(ikm + 96, dh3, 32u);
    memcpy(info, kc_hs_sk_label, sizeof(kc_hs_sk_label) - 1u);
    crypto_blake2b_init(&ctx, 32u);
    crypto_blake2b_update(&ctx, offer, KC_HANDSHAKE_SIZE);
    crypto_blake2b_update(&ctx, answer, KC_HANDSHAKE_SIZE);
    crypto_blake2b_final(&ctx, info + sizeof(kc_hs_sk_label) - 1u);
    kc_hkdf(NULL, 0u, ikm, sizeof(ikm), info, sizeof(info), out, 96u);
    crypto_wipe(ikm, sizeof(ikm));
    crypto_wipe(&ctx, sizeof(ctx));
}

static kc_status kc_hs_encode(const uint8_t *handshake,
                              uint8_t *out_text,
                              size_t text_cap,
                              size_t *text_len)
{
    if (text_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_text == NULL || text_cap < KC_HANDSHAKE_TEXT_BOUND) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    return kc_alphabet_encode(handshake, KC_HANDSHAKE_SIZE, out_text, text_cap,
                              text_len);
}

kc_status kc_handshake_peek(const uint8_t *text,
                            size_t text_len,
                            uint8_t *out_type,
                            uint8_t *out_offer_id,
                            size_t offer_id_cap,
                            uint8_t *out_public,
                            size_t public_cap)
{
    uint8_t handshake[KC_HANDSHAKE_SIZE];
    kc_status status;

    if (out_type == NULL || out_offer_id == NULL || out_public == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (offer_id_cap < KC_OFFER_ID_SIZE || public_cap < KC_PUBLIC_KEY_SIZE) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_handshake_decode(text, text_len, handshake);
    if (status != KC_OK) {
        return status;
    }
    *out_type = handshake[1];
    memcpy(out_offer_id, handshake + KC_HS_OFFSET_ID, KC_OFFER_ID_SIZE);
    memcpy(out_public, handshake + KC_HS_OFFSET_IK, KC_PUBLIC_KEY_SIZE);
    return KC_OK;
}

kc_status kc_session_offer(const uint8_t *identity,
                           size_t identity_len,
                           int64_t chat_id,
                           int64_t my_id,
                           int64_t peer_id,
                           const uint8_t *random,
                           size_t random_len,
                           uint8_t *out_text,
                           size_t text_cap,
                           size_t *text_len,
                           uint8_t *out_pending,
                           size_t pending_cap,
                           size_t *pending_len)
{
    uint8_t offer[KC_HANDSHAKE_SIZE];
    uint8_t seed[32];
    uint8_t ek_secret[32];
    uint8_t message[KC_HS_SIGN_MAX];
    size_t message_len;
    kc_status status;

    status = kc_identity_check(identity, identity_len);
    if (status != KC_OK) {
        return status;
    }
    if (random == NULL || random_len != KC_OFFER_RANDOM_SIZE ||
        text_len == NULL || pending_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_text == NULL || text_cap < KC_HANDSHAKE_TEXT_BOUND ||
        out_pending == NULL || pending_cap < KC_PENDING_STATE_SIZE) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    memcpy(seed, random, sizeof(seed));
    offer[0] = KC_V3_VERSION;
    offer[1] = KC_V3_OFFER;
    memcpy(offer + KC_HS_OFFSET_ID, random + 32, KC_OFFER_ID_SIZE);
    memcpy(offer + KC_HS_OFFSET_IK, identity + KC_SEED_SIZE,
           KC_PUBLIC_KEY_SIZE);
    crypto_elligator_key_pair(offer + KC_HS_OFFSET_EK, ek_secret, seed);
    message_len = kc_hs_sign_message(message, kc_hs_offer_label,
                                     sizeof(kc_hs_offer_label) - 1u, chat_id,
                                     my_id, peer_id, offer, NULL);
    kc_identity_sign(identity, message, message_len, offer + KC_HS_OFFSET_SIG);

    out_pending[0] = KC_PENDING_FMT;
    kc_store_i64(out_pending + 1, chat_id);
    kc_store_i64(out_pending + 9, my_id);
    kc_store_i64(out_pending + 17, peer_id);
    memcpy(out_pending + 25, offer + KC_HS_OFFSET_ID, KC_OFFER_ID_SIZE);
    memcpy(out_pending + KC_HS_PENDING_OFFSET_EK, ek_secret, 32u);
    memcpy(out_pending + KC_HS_PENDING_OFFSET_OFFER, offer, KC_HANDSHAKE_SIZE);
    *pending_len = KC_PENDING_STATE_SIZE;
    status = kc_hs_encode(offer, out_text, text_cap, text_len);
    crypto_wipe(ek_secret, sizeof(ek_secret));
    if (status != KC_OK) {
        crypto_wipe(out_pending, KC_PENDING_STATE_SIZE);
    }
    return status;
}

static kc_status kc_hs_verify(const uint8_t *handshake,
                              const uint8_t *label,
                              size_t label_len,
                              int64_t chat_id,
                              int64_t from_id,
                              int64_t to_id,
                              const uint8_t *offer_hash)
{
    uint8_t message[KC_HS_SIGN_MAX];
    size_t message_len = kc_hs_sign_message(message, label, label_len, chat_id,
                                            from_id, to_id, handshake,
                                            offer_hash);

    return kc_identity_verify(handshake + KC_HS_OFFSET_IK, message, message_len,
                              handshake + KC_HS_OFFSET_SIG)
               ? KC_OK
               : KC_ERR_BAD_SIGNATURE;
}

static void kc_hs_init_common(kc_session *session,
                              int64_t chat_id,
                              int64_t my_id,
                              int64_t peer_id,
                              const uint8_t *offer_id,
                              const uint8_t *peer_ik,
                              const uint8_t *secret)
{
    memset(session, 0, sizeof(*session));
    session->chat_id = chat_id;
    session->my_id = my_id;
    session->peer_id = peer_id;
    memcpy(session->offer_id, offer_id, KC_OFFER_ID_SIZE);
    memcpy(session->peer_ik, peer_ik, KC_PUBLIC_KEY_SIZE);
    memcpy(session->rk, secret, 32u);
    memcpy(session->ok, secret + 64, 32u);
}

kc_status kc_session_answer(const uint8_t *identity,
                            size_t identity_len,
                            int64_t chat_id,
                            int64_t my_id,
                            int64_t peer_id,
                            const uint8_t *offer_text,
                            size_t offer_len,
                            const uint8_t *old_state,
                            size_t old_state_len,
                            const uint8_t *random,
                            size_t random_len,
                            uint8_t *out_text,
                            size_t text_cap,
                            size_t *text_len,
                            uint8_t *out_state,
                            size_t state_cap,
                            size_t *state_len)
{
    uint8_t offer[KC_HANDSHAKE_SIZE];
    uint8_t answer[KC_HANDSHAKE_SIZE];
    uint8_t offer_hash[32];
    uint8_t seed[32];
    uint8_t ek_secret[32];
    uint8_t ik_secret[32];
    uint8_t peer_ik_x[32];
    uint8_t dh1[32];
    uint8_t dh2[32];
    uint8_t dh3[32];
    uint8_t secret[96];
    uint8_t message[KC_HS_SIGN_MAX];
    size_t message_len;
    kc_session *session;
    kc_status status;

    status = kc_identity_check(identity, identity_len);
    if (status != KC_OK) {
        return status;
    }
    if (random == NULL || random_len != KC_ANSWER_RANDOM_SIZE ||
        text_len == NULL || state_len == NULL ||
        (old_state == NULL && old_state_len != 0u)) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_text == NULL || text_cap < KC_HANDSHAKE_TEXT_BOUND ||
        out_state == NULL || state_cap < KC_SESSION_FIXED_SIZE) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_handshake_decode(offer_text, offer_len, offer);
    if (status != KC_OK) {
        return status;
    }
    if (offer[1] != KC_V3_OFFER) {
        return KC_ERR_HANDSHAKE_MESSAGE;
    }
    status = kc_hs_verify(offer, kc_hs_offer_label,
                          sizeof(kc_hs_offer_label) - 1u, chat_id, peer_id,
                          my_id, NULL);
    if (status != KC_OK) {
        return status;
    }
    session = (kc_session *)malloc(sizeof(*session));
    if (session == NULL) {
        return KC_ERR_OUT_OF_MEMORY;
    }
    if (old_state_len != 0u) {
        status = kc_session_parse(old_state, old_state_len, session);
        if (status == KC_OK &&
            memcmp(session->offer_id, offer + KC_HS_OFFSET_ID,
                   KC_OFFER_ID_SIZE) == 0) {
            status = KC_ERR_REPLAY;
        }
        kc_session_wipe(session);
        if (status != KC_OK) {
            free(session);
            return status;
        }
    }

    memcpy(seed, random, sizeof(seed));
    answer[0] = KC_V3_VERSION;
    answer[1] = KC_V3_ANSWER;
    memcpy(answer + KC_HS_OFFSET_ID, offer + KC_HS_OFFSET_ID, KC_OFFER_ID_SIZE);
    memcpy(answer + KC_HS_OFFSET_IK, identity + KC_SEED_SIZE,
           KC_PUBLIC_KEY_SIZE);
    crypto_elligator_key_pair(answer + KC_HS_OFFSET_EK, ek_secret, seed);
    kc_hs_offer_hash(offer, offer_hash);
    message_len = kc_hs_sign_message(message, kc_hs_answer_label,
                                     sizeof(kc_hs_answer_label) - 1u, chat_id,
                                     my_id, peer_id, answer, offer_hash);
    kc_identity_sign(identity, message, message_len, answer + KC_HS_OFFSET_SIG);

    kc_identity_x25519_secret(identity, ik_secret);
    kc_identity_x25519_public(offer + KC_HS_OFFSET_IK, peer_ik_x);
    status = kc_ratchet_dh_public(dh1, ek_secret, peer_ik_x);
    if (status == KC_OK) {
        status = kc_ratchet_dh_repr(dh2, ik_secret, offer + KC_HS_OFFSET_EK);
    }
    if (status == KC_OK) {
        status = kc_ratchet_dh_repr(dh3, ek_secret, offer + KC_HS_OFFSET_EK);
    }
    if (status == KC_OK) {
        kc_hs_secret(dh1, dh2, dh3, offer, answer, secret);
        kc_hs_init_common(session, chat_id, my_id, peer_id,
                          offer + KC_HS_OFFSET_ID, offer + KC_HS_OFFSET_IK,
                          secret);
        memcpy(session->dhs_priv, ek_secret, 32u);
        memcpy(session->dhs_repr, answer + KC_HS_OFFSET_EK, 32u);
        memcpy(session->cks, secret + 32, 32u);
        status = kc_session_serialize(session, out_state, state_cap, state_len);
    }
    if (status == KC_OK) {
        status = kc_hs_encode(answer, out_text, text_cap, text_len);
    }
    crypto_wipe(ek_secret, sizeof(ek_secret));
    crypto_wipe(ik_secret, sizeof(ik_secret));
    crypto_wipe(dh1, sizeof(dh1));
    crypto_wipe(dh2, sizeof(dh2));
    crypto_wipe(dh3, sizeof(dh3));
    crypto_wipe(secret, sizeof(secret));
    kc_session_wipe(session);
    free(session);
    if (status != KC_OK) {
        crypto_wipe(out_state, state_cap);
    }
    return status;
}

kc_status kc_session_accept(const uint8_t *identity,
                            size_t identity_len,
                            const uint8_t *pending,
                            size_t pending_len,
                            const uint8_t *answer_text,
                            size_t answer_len,
                            const uint8_t *expected_peer,
                            size_t expected_peer_len,
                            const uint8_t *random,
                            size_t random_len,
                            uint8_t *out_state,
                            size_t state_cap,
                            size_t *state_len)
{
    uint8_t answer[KC_HANDSHAKE_SIZE];
    const uint8_t *offer;
    uint8_t offer_hash[32];
    uint8_t ek_secret[32];
    uint8_t ik_secret[32];
    uint8_t peer_ik_x[32];
    uint8_t dh1[32];
    uint8_t dh2[32];
    uint8_t dh3[32];
    uint8_t secret[96];
    int64_t chat_id;
    int64_t my_id;
    int64_t peer_id;
    kc_session *session;
    kc_status status;

    status = kc_identity_check(identity, identity_len);
    if (status != KC_OK) {
        return status;
    }
    if (random == NULL || random_len != KC_ACCEPT_RANDOM_SIZE ||
        state_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (expected_peer_len != 0u &&
        (expected_peer == NULL || expected_peer_len != KC_PUBLIC_KEY_SIZE)) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (pending == NULL || pending_len != KC_PENDING_STATE_SIZE ||
        pending[0] != KC_PENDING_FMT) {
        return KC_ERR_BAD_STATE;
    }
    if (out_state == NULL || state_cap < KC_SESSION_FIXED_SIZE) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_handshake_decode(answer_text, answer_len, answer);
    if (status != KC_OK) {
        return status;
    }
    if (answer[1] != KC_V3_ANSWER) {
        return KC_ERR_HANDSHAKE_MESSAGE;
    }
    if (expected_peer_len != 0u &&
        crypto_verify32(answer + KC_HS_OFFSET_IK, expected_peer) != 0) {
        return KC_ERR_BAD_PEER;
    }
    chat_id = kc_load_i64(pending + 1);
    my_id = kc_load_i64(pending + 9);
    peer_id = kc_load_i64(pending + 17);
    offer = pending + KC_HS_PENDING_OFFSET_OFFER;
    if (memcmp(offer + KC_HS_OFFSET_IK, identity + KC_SEED_SIZE,
               KC_PUBLIC_KEY_SIZE) != 0) {
        return KC_ERR_BAD_STATE;
    }
    if (memcmp(answer + KC_HS_OFFSET_ID, offer + KC_HS_OFFSET_ID,
               KC_OFFER_ID_SIZE) != 0) {
        return KC_ERR_REPLAY;
    }
    kc_hs_offer_hash(offer, offer_hash);
    status = kc_hs_verify(answer, kc_hs_answer_label,
                          sizeof(kc_hs_answer_label) - 1u, chat_id, peer_id,
                          my_id, offer_hash);
    if (status != KC_OK) {
        return status;
    }
    session = (kc_session *)malloc(sizeof(*session));
    if (session == NULL) {
        return KC_ERR_OUT_OF_MEMORY;
    }
    memcpy(ek_secret, pending + KC_HS_PENDING_OFFSET_EK, 32u);
    kc_identity_x25519_secret(identity, ik_secret);
    kc_identity_x25519_public(answer + KC_HS_OFFSET_IK, peer_ik_x);
    status = kc_ratchet_dh_repr(dh1, ik_secret, answer + KC_HS_OFFSET_EK);
    if (status == KC_OK) {
        status = kc_ratchet_dh_public(dh2, ek_secret, peer_ik_x);
    }
    if (status == KC_OK) {
        status = kc_ratchet_dh_repr(dh3, ek_secret, answer + KC_HS_OFFSET_EK);
    }
    if (status == KC_OK) {
        kc_hs_secret(dh1, dh2, dh3, offer, answer, secret);
        kc_hs_init_common(session, chat_id, my_id, peer_id,
                          offer + KC_HS_OFFSET_ID, answer + KC_HS_OFFSET_IK,
                          secret);
        session->flags = KC_FLAG_INITIATOR | KC_FLAG_HAS_DHR | KC_FLAG_HAS_CKR;
        memcpy(session->dhr_repr, answer + KC_HS_OFFSET_EK, 32u);
        memcpy(session->ckr, secret + 32, 32u);
        status = kc_ratchet_send_step(session, random);
    }
    if (status == KC_OK) {
        status = kc_session_serialize(session, out_state, state_cap, state_len);
    }
    crypto_wipe(ek_secret, sizeof(ek_secret));
    crypto_wipe(ik_secret, sizeof(ik_secret));
    crypto_wipe(dh1, sizeof(dh1));
    crypto_wipe(dh2, sizeof(dh2));
    crypto_wipe(dh3, sizeof(dh3));
    crypto_wipe(secret, sizeof(secret));
    kc_session_wipe(session);
    free(session);
    if (status != KC_OK) {
        crypto_wipe(out_state, state_cap);
    }
    return status;
}
