#include "kc_internal.h"

#include <stdint.h>

const char *kc_status_string(kc_status status)
{
    switch (status) {
    case KC_OK:
        return "ok";
    case KC_ERR_EMPTY_PASSWORD:
        return "empty_password";
    case KC_ERR_BAD_KEY_LENGTH:
        return "bad_key_length";
    case KC_ERR_NOT_ENCRYPTED:
        return "not_encrypted";
    case KC_ERR_MALFORMED:
        return "malformed";
    case KC_ERR_WRONG_KEY:
        return "wrong_key";
    case KC_ERR_INTERNAL:
        return "internal";
    case KC_ERR_BUFFER_TOO_SMALL:
        return "buffer_too_small";
    case KC_ERR_INVALID_ARGUMENT:
        return "invalid_argument";
    case KC_ERR_OUT_OF_MEMORY:
        return "out_of_memory";
    case KC_ERR_BAD_SIGNATURE:
        return "bad_signature";
    case KC_ERR_BAD_STATE:
        return "bad_state";
    case KC_ERR_TOO_MANY_SKIPPED:
        return "too_many_skipped";
    case KC_ERR_REPLAY:
        return "replay";
    case KC_ERR_BAD_PEER:
        return "bad_peer";
    case KC_ERR_UNSUPPORTED_VERSION:
        return "unsupported_version";
    case KC_ERR_HANDSHAKE_MESSAGE:
        return "handshake_message";
    case KC_ERR_TOO_LONG:
        return "too_long";
    case KC_ERR_AWAITING_PEER:
        return "awaiting_peer";
    default:
        return "unknown";
    }
}

int kc_size_add(size_t left, size_t right, size_t *out)
{
    if (out == NULL || left > SIZE_MAX - right) {
        return 0;
    }
    *out = left + right;
    return 1;
}
