#include "kc_session_state.h"

#include "kc_codec.h"
#include "monocypher.h"
#include <string.h>

kc_status kc_session_parse(const uint8_t *blob,
                           size_t blob_len,
                           kc_session *session)
{
    const uint8_t *cursor;
    size_t index;

    if (blob == NULL || session == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (blob_len < KC_SESSION_FIXED_SIZE || blob[0] != KC_SESSION_FMT) {
        return KC_ERR_BAD_STATE;
    }
    memset(session, 0, sizeof(*session));
    cursor = blob + 1;
    session->flags = *cursor++;
    if ((session->flags & ~KC_FLAG_MASK) != 0u) {
        return KC_ERR_BAD_STATE;
    }
    session->chat_id = kc_load_i64(cursor);
    cursor += 8;
    session->my_id = kc_load_i64(cursor);
    cursor += 8;
    session->peer_id = kc_load_i64(cursor);
    cursor += 8;
    memcpy(session->offer_id, cursor, KC_OFFER_ID_SIZE);
    cursor += KC_OFFER_ID_SIZE;
    memcpy(session->peer_ik, cursor, 32u);
    cursor += 32;
    memcpy(session->rk, cursor, 32u);
    cursor += 32;
    memcpy(session->ok, cursor, 32u);
    cursor += 32;
    memcpy(session->dhs_priv, cursor, 32u);
    cursor += 32;
    memcpy(session->dhs_repr, cursor, 32u);
    cursor += 32;
    memcpy(session->dhr_repr, cursor, 32u);
    cursor += 32;
    memcpy(session->cks, cursor, 32u);
    cursor += 32;
    memcpy(session->ckr, cursor, 32u);
    cursor += 32;
    session->ns = kc_load_u32(cursor);
    cursor += 4;
    session->nr = kc_load_u32(cursor);
    cursor += 4;
    session->pn = kc_load_u32(cursor);
    cursor += 4;
    session->nskip = (uint16_t)(((uint16_t)cursor[0] << 8u) | cursor[1]);
    cursor += 2;
    if (session->nskip > KC_V3_MAX_SKIP_ENTRIES ||
        blob_len != KC_SESSION_FIXED_SIZE +
                        (size_t)session->nskip * KC_SKIPPED_ENTRY_SIZE) {
        memset(session, 0, sizeof(*session));
        return KC_ERR_BAD_STATE;
    }
    for (index = 0u; index < session->nskip; index++) {
        memcpy(session->skipped[index].dhr, cursor, 32u);
        cursor += 32;
        session->skipped[index].n = kc_load_u32(cursor);
        cursor += 4;
        memcpy(session->skipped[index].mk, cursor, 32u);
        cursor += 32;
    }
    return KC_OK;
}

size_t kc_session_serialized_size(const kc_session *session)
{
    return KC_SESSION_FIXED_SIZE +
           (size_t)session->nskip * KC_SKIPPED_ENTRY_SIZE;
}

kc_status kc_session_serialize(const kc_session *session,
                               uint8_t *out,
                               size_t out_cap,
                               size_t *out_len)
{
    uint8_t *cursor;
    size_t required;
    size_t index;

    if (session == NULL || out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    required = kc_session_serialized_size(session);
    if (out == NULL || out_cap < required) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    cursor = out;
    *cursor++ = KC_SESSION_FMT;
    *cursor++ = session->flags;
    kc_store_i64(cursor, session->chat_id);
    cursor += 8;
    kc_store_i64(cursor, session->my_id);
    cursor += 8;
    kc_store_i64(cursor, session->peer_id);
    cursor += 8;
    memcpy(cursor, session->offer_id, KC_OFFER_ID_SIZE);
    cursor += KC_OFFER_ID_SIZE;
    memcpy(cursor, session->peer_ik, 32u);
    cursor += 32;
    memcpy(cursor, session->rk, 32u);
    cursor += 32;
    memcpy(cursor, session->ok, 32u);
    cursor += 32;
    memcpy(cursor, session->dhs_priv, 32u);
    cursor += 32;
    memcpy(cursor, session->dhs_repr, 32u);
    cursor += 32;
    memcpy(cursor, session->dhr_repr, 32u);
    cursor += 32;
    memcpy(cursor, session->cks, 32u);
    cursor += 32;
    memcpy(cursor, session->ckr, 32u);
    cursor += 32;
    kc_store_u32(cursor, session->ns);
    cursor += 4;
    kc_store_u32(cursor, session->nr);
    cursor += 4;
    kc_store_u32(cursor, session->pn);
    cursor += 4;
    *cursor++ = (uint8_t)(session->nskip >> 8u);
    *cursor++ = (uint8_t)session->nskip;
    for (index = 0u; index < session->nskip; index++) {
        memcpy(cursor, session->skipped[index].dhr, 32u);
        cursor += 32;
        kc_store_u32(cursor, session->skipped[index].n);
        cursor += 4;
        memcpy(cursor, session->skipped[index].mk, 32u);
        cursor += 32;
    }
    *out_len = required;
    return KC_OK;
}

void kc_session_wipe(kc_session *session)
{
    if (session != NULL) {
        crypto_wipe(session, sizeof(*session));
    }
}

int kc_session_skipped_take(kc_session *session,
                            const uint8_t dhr[32],
                            uint32_t n,
                            uint8_t out_mk[32])
{
    size_t index;

    for (index = 0u; index < session->nskip; index++) {
        kc_skipped_key *entry = &session->skipped[index];
        if (entry->n == n && memcmp(entry->dhr, dhr, 32u) == 0) {
            memcpy(out_mk, entry->mk, 32u);
            crypto_wipe(entry, sizeof(*entry));
            if (index + 1u < session->nskip) {
                memmove(entry, entry + 1,
                        (session->nskip - index - 1u) * sizeof(*entry));
                crypto_wipe(&session->skipped[session->nskip - 1u],
                            sizeof(*entry));
            }
            session->nskip--;
            return 1;
        }
    }
    return 0;
}

void kc_session_skipped_push(kc_session *session,
                             const uint8_t dhr[32],
                             uint32_t n,
                             const uint8_t mk[32])
{
    kc_skipped_key *entry;

    if (session->nskip == KC_V3_MAX_SKIP_ENTRIES) {
        crypto_wipe(&session->skipped[0], sizeof(*entry));
        memmove(&session->skipped[0], &session->skipped[1],
                (KC_V3_MAX_SKIP_ENTRIES - 1u) * sizeof(*entry));
        session->nskip--;
    }
    entry = &session->skipped[session->nskip];
    memcpy(entry->dhr, dhr, 32u);
    entry->n = n;
    memcpy(entry->mk, mk, 32u);
    session->nskip++;
}
