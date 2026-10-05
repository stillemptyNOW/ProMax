#ifndef KC_RATCHET_H
#define KC_RATCHET_H

#include <stddef.h>
#include <stdint.h>

#include "kc_session_state.h"

kc_status kc_ratchet_dh_repr(uint8_t out[32],
                             const uint8_t secret[32],
                             const uint8_t peer_repr[32]);
kc_status kc_ratchet_dh_public(uint8_t out[32],
                               const uint8_t secret[32],
                               const uint8_t peer_public[32]);
kc_status kc_ratchet_send_step(kc_session *session, const uint8_t *seed);
kc_status kc_ratchet_next_send_key(kc_session *session,
                                   const uint8_t *seed,
                                   uint8_t out_mk[32],
                                   uint32_t *out_n,
                                   uint32_t *out_pn,
                                   uint8_t out_repr[32]);
kc_status kc_ratchet_receive_key(kc_session *session,
                                 const uint8_t repr[32],
                                 uint32_t pn,
                                 uint32_t n,
                                 uint8_t out_mk[32]);

#endif
