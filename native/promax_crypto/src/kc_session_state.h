#ifndef KC_SESSION_STATE_H
#define KC_SESSION_STATE_H

#include <stddef.h>
#include <stdint.h>

#include "kc_internal.h"

#define KC_SESSION_FMT 0x03u
#define KC_PENDING_FMT 0x03u
#define KC_SESSION_FIXED_SIZE 304u
#define KC_SKIPPED_ENTRY_SIZE 68u

#define KC_FLAG_FORCE_DH 0x01u
#define KC_FLAG_INITIATOR 0x02u
#define KC_FLAG_HAS_DHR 0x04u
#define KC_FLAG_HAS_CKR 0x08u
#define KC_FLAG_NEEDS_DH 0x10u
#define KC_FLAG_MASK 0x1Fu

typedef struct {
    uint8_t dhr[32];
    uint32_t n;
    uint8_t mk[32];
} kc_skipped_key;

typedef struct {
    uint8_t flags;
    int64_t chat_id;
    int64_t my_id;
    int64_t peer_id;
    uint8_t offer_id[KC_OFFER_ID_SIZE];
    uint8_t peer_ik[32];
    uint8_t rk[32];
    uint8_t ok[32];
    uint8_t dhs_priv[32];
    uint8_t dhs_repr[32];
    uint8_t dhr_repr[32];
    uint8_t cks[32];
    uint8_t ckr[32];
    uint32_t ns;
    uint32_t nr;
    uint32_t pn;
    uint16_t nskip;
    kc_skipped_key skipped[256];
} kc_session;

kc_status kc_session_parse(const uint8_t *blob,
                           size_t blob_len,
                           kc_session *session);
size_t kc_session_serialized_size(const kc_session *session);
kc_status kc_session_serialize(const kc_session *session,
                               uint8_t *out,
                               size_t out_cap,
                               size_t *out_len);
void kc_session_wipe(kc_session *session);
int kc_session_skipped_take(kc_session *session,
                            const uint8_t dhr[32],
                            uint32_t n,
                            uint8_t out_mk[32]);
void kc_session_skipped_push(kc_session *session,
                             const uint8_t dhr[32],
                             uint32_t n,
                             const uint8_t mk[32]);

#endif
