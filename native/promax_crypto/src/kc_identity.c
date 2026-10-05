#include "kc_identity.h"

#include "kc_codec.h"
#include "monocypher.h"
#include <string.h>

#define KC_FINGERPRINT_ITERATIONS 5200u
#define KC_FINGERPRINT_HALF 30u

kc_status kc_identity_check(const uint8_t *identity, size_t identity_len)
{
    if (identity == NULL || identity_len != KC_IDENTITY_SIZE) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    return KC_OK;
}

void kc_identity_x25519_secret(const uint8_t *identity, uint8_t out[32])
{
    uint8_t digest[64];

    crypto_blake2b(digest, sizeof(digest), identity, KC_SEED_SIZE);
    crypto_eddsa_trim_scalar(out, digest);
    crypto_wipe(digest, sizeof(digest));
}

void kc_identity_x25519_public(const uint8_t eddsa_public[32], uint8_t out[32])
{
    crypto_eddsa_to_x25519(out, eddsa_public);
}

void kc_identity_sign(const uint8_t *identity,
                      const uint8_t *message,
                      size_t message_len,
                      uint8_t out_signature[64])
{
    crypto_eddsa_sign(out_signature, identity, message, message_len);
}

int kc_identity_verify(const uint8_t eddsa_public[32],
                       const uint8_t *message,
                       size_t message_len,
                       const uint8_t signature[64])
{
    return crypto_eddsa_check(signature, eddsa_public, message, message_len) ==
           0;
}

kc_status kc_identity_create(const uint8_t *seed,
                             size_t seed_len,
                             uint8_t *out_identity,
                             size_t out_cap,
                             size_t *out_len)
{
    uint8_t seed_copy[KC_SEED_SIZE];
    uint8_t public_key[KC_PUBLIC_KEY_SIZE];

    if (seed == NULL || seed_len != KC_SEED_SIZE || out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_identity == NULL || out_cap < KC_IDENTITY_SIZE) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    memcpy(seed_copy, seed, sizeof(seed_copy));
    crypto_eddsa_key_pair(out_identity, public_key, seed_copy);
    crypto_wipe(public_key, sizeof(public_key));
    *out_len = KC_IDENTITY_SIZE;
    return KC_OK;
}

kc_status kc_identity_public_key(const uint8_t *identity,
                                 size_t identity_len,
                                 uint8_t *out_public,
                                 size_t out_cap,
                                 size_t *out_len)
{
    kc_status status = kc_identity_check(identity, identity_len);

    if (status != KC_OK) {
        return status;
    }
    if (out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_public == NULL || out_cap < KC_PUBLIC_KEY_SIZE) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    memcpy(out_public, identity + KC_SEED_SIZE, KC_PUBLIC_KEY_SIZE);
    *out_len = KC_PUBLIC_KEY_SIZE;
    return KC_OK;
}

static void kc_fingerprint_half(int64_t user_id,
                                const uint8_t *public_key,
                                uint8_t *out)
{
    static const uint8_t version = 0x03u;
    uint8_t id_bytes[8];
    uint8_t hash[32];
    crypto_blake2b_ctx ctx;
    unsigned int iteration;
    size_t group;

    kc_store_i64(id_bytes, user_id);
    crypto_blake2b_init(&ctx, sizeof(hash));
    crypto_blake2b_update(&ctx, &version, 1u);
    crypto_blake2b_update(&ctx, id_bytes, sizeof(id_bytes));
    crypto_blake2b_update(&ctx, public_key, KC_PUBLIC_KEY_SIZE);
    crypto_blake2b_final(&ctx, hash);
    for (iteration = 1u; iteration < KC_FINGERPRINT_ITERATIONS; iteration++) {
        crypto_blake2b_init(&ctx, sizeof(hash));
        crypto_blake2b_update(&ctx, hash, sizeof(hash));
        crypto_blake2b_update(&ctx, public_key, KC_PUBLIC_KEY_SIZE);
        crypto_blake2b_final(&ctx, hash);
    }
    for (group = 0u; group < 6u; group++) {
        uint64_t value = 0u;
        size_t index;
        size_t digit;
        for (index = 0u; index < 5u; index++) {
            value = (value << 8u) | hash[group * 5u + index];
        }
        value %= 100000u;
        for (digit = 5u; digit > 0u; digit--) {
            out[group * 5u + digit - 1u] = (uint8_t)('0' + value % 10u);
            value /= 10u;
        }
    }
}

kc_status kc_fingerprint(int64_t my_id,
                         const uint8_t *my_public,
                         size_t my_public_len,
                         int64_t peer_id,
                         const uint8_t *peer_public,
                         size_t peer_public_len,
                         uint8_t *out_digits,
                         size_t out_cap,
                         size_t *out_len)
{
    int mine_first;

    if (my_public == NULL || my_public_len != KC_PUBLIC_KEY_SIZE ||
        peer_public == NULL || peer_public_len != KC_PUBLIC_KEY_SIZE ||
        out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_digits == NULL || out_cap < KC_FINGERPRINT_DIGITS) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    mine_first = my_id < peer_id ||
                 (my_id == peer_id &&
                  memcmp(my_public, peer_public, KC_PUBLIC_KEY_SIZE) <= 0);
    kc_fingerprint_half(mine_first ? my_id : peer_id,
                        mine_first ? my_public : peer_public, out_digits);
    kc_fingerprint_half(mine_first ? peer_id : my_id,
                        mine_first ? peer_public : my_public,
                        out_digits + KC_FINGERPRINT_HALF);
    *out_len = KC_FINGERPRINT_DIGITS;
    return KC_OK;
}
