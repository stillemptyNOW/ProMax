#include "kc_ratchet.h"

#include "kc_hkdf.h"
#include "monocypher.h"
#include <string.h>

static const uint8_t kc_ratchet_zero[32] = {0u};

static kc_status kc_ratchet_check_dh(const uint8_t out[32])
{
    return crypto_verify32(out, kc_ratchet_zero) == 0 ? KC_ERR_BAD_PEER
                                                       : KC_OK;
}

kc_status kc_ratchet_dh_repr(uint8_t out[32],
                             const uint8_t secret[32],
                             const uint8_t peer_repr[32])
{
    uint8_t curve[32];
    kc_status status;

    crypto_elligator_map(curve, peer_repr);
    crypto_x25519(out, secret, curve);
    status = kc_ratchet_check_dh(out);
    crypto_wipe(curve, sizeof(curve));
    return status;
}

kc_status kc_ratchet_dh_public(uint8_t out[32],
                               const uint8_t secret[32],
                               const uint8_t peer_public[32])
{
    crypto_x25519(out, secret, peer_public);
    return kc_ratchet_check_dh(out);
}

kc_status kc_ratchet_send_step(kc_session *session, const uint8_t *seed)
{
    uint8_t seed_copy[32];
    uint8_t secret[32];
    uint8_t hidden[32];
    uint8_t dh[32];
    kc_status status;

    if ((session->flags & KC_FLAG_HAS_DHR) == 0u) {
        if ((session->flags & KC_FLAG_FORCE_DH) != 0u) {
            return KC_ERR_AWAITING_PEER;
        }
        session->flags &= (uint8_t)(KC_FLAG_MASK ^ KC_FLAG_NEEDS_DH);
        return KC_OK;
    }
    memcpy(seed_copy, seed, sizeof(seed_copy));
    crypto_elligator_key_pair(hidden, secret, seed_copy);
    status = kc_ratchet_dh_repr(dh, secret, session->dhr_repr);
    if (status == KC_OK) {
        kc_kdf_root(session->rk, dh, session->rk, session->cks);
        memcpy(session->dhs_priv, secret, 32u);
        memcpy(session->dhs_repr, hidden, 32u);
        session->pn = session->ns;
        session->ns = 0u;
        session->flags &=
            (uint8_t)(KC_FLAG_MASK ^ (KC_FLAG_FORCE_DH | KC_FLAG_NEEDS_DH));
    }
    crypto_wipe(secret, sizeof(secret));
    crypto_wipe(dh, sizeof(dh));
    return status;
}

kc_status kc_ratchet_next_send_key(kc_session *session,
                                   const uint8_t *seed,
                                   uint8_t out_mk[32],
                                   uint32_t *out_n,
                                   uint32_t *out_pn,
                                   uint8_t out_repr[32])
{
    if ((session->flags & (KC_FLAG_NEEDS_DH | KC_FLAG_FORCE_DH)) != 0u) {
        kc_status status = kc_ratchet_send_step(session, seed);
        if (status != KC_OK) {
            return status;
        }
    }
    if (session->ns == UINT32_MAX) {
        return KC_ERR_BAD_STATE;
    }
    kc_kdf_chain(session->cks, session->cks, out_mk);
    *out_n = session->ns;
    *out_pn = session->pn;
    memcpy(out_repr, session->dhs_repr, 32u);
    session->ns++;
    return KC_OK;
}

static kc_status kc_ratchet_advance(kc_session *session,
                                    uint32_t until,
                                    int strict)
{
    uint8_t mk[32];

    if ((session->flags & KC_FLAG_HAS_CKR) == 0u || until <= session->nr) {
        return KC_OK;
    }
    if (until - session->nr > KC_V3_MAX_ADVANCE) {
        return strict ? KC_ERR_TOO_MANY_SKIPPED : KC_OK;
    }
    while (session->nr < until) {
        kc_kdf_chain(session->ckr, session->ckr, mk);
        if (until - session->nr <= KC_V3_MAX_SKIP) {
            kc_session_skipped_push(session, session->dhr_repr, session->nr, mk);
        }
        session->nr++;
    }
    crypto_wipe(mk, sizeof(mk));
    return KC_OK;
}

kc_status kc_ratchet_receive_key(kc_session *session,
                                 const uint8_t repr[32],
                                 uint32_t pn,
                                 uint32_t n,
                                 uint8_t out_mk[32])
{
    kc_status status;

    if (kc_session_skipped_take(session, repr, n, out_mk)) {
        return KC_OK;
    }
    if ((session->flags & KC_FLAG_HAS_DHR) == 0u ||
        memcmp(repr, session->dhr_repr, 32u) != 0) {
        uint8_t dh[32];
        if (n > KC_V3_MAX_ADVANCE) {
            return KC_ERR_TOO_MANY_SKIPPED;
        }
        (void)kc_ratchet_advance(session, pn, 0);
        status = kc_ratchet_dh_repr(dh, session->dhs_priv, repr);
        if (status != KC_OK) {
            return status;
        }
        kc_kdf_root(session->rk, dh, session->rk, session->ckr);
        crypto_wipe(dh, sizeof(dh));
        memcpy(session->dhr_repr, repr, 32u);
        session->nr = 0u;
        session->flags |= KC_FLAG_HAS_DHR | KC_FLAG_HAS_CKR | KC_FLAG_NEEDS_DH;
    } else if ((session->flags & KC_FLAG_HAS_CKR) == 0u) {
        return KC_ERR_BAD_STATE;
    } else if (n < session->nr) {
        return KC_ERR_REPLAY;
    }
    status = kc_ratchet_advance(session, n, 1);
    if (status != KC_OK) {
        return status;
    }
    if (session->nr == UINT32_MAX) {
        return KC_ERR_BAD_STATE;
    }
    kc_kdf_chain(session->ckr, session->ckr, out_mk);
    session->nr++;
    return KC_OK;
}
