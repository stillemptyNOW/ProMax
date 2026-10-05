#include "kc_hkdf.h"

#include "monocypher.h"
#include <string.h>

static const uint8_t kc_hkdf_zero_salt[32] = {0u};
static const uint8_t kc_hkdf_root_info[] = "promax-v3/rk";
static const uint8_t kc_hkdf_message_info[] = "promax-v3/mk";

void kc_hkdf(const uint8_t *salt,
             size_t salt_len,
             const uint8_t *ikm,
             size_t ikm_len,
             const uint8_t *info,
             size_t info_len,
             uint8_t *out,
             size_t out_len)
{
    uint8_t prk[32];
    uint8_t block[32];
    size_t block_len = 0u;
    size_t offset = 0u;
    uint8_t counter = 0u;
    crypto_blake2b_ctx ctx;

    if (salt_len == 0u) {
        salt = kc_hkdf_zero_salt;
        salt_len = sizeof(kc_hkdf_zero_salt);
    }
    crypto_blake2b_keyed(prk, sizeof(prk), salt, salt_len, ikm, ikm_len);
    while (offset < out_len) {
        size_t take;
        counter++;
        crypto_blake2b_keyed_init(&ctx, sizeof(block), prk, sizeof(prk));
        crypto_blake2b_update(&ctx, block, block_len);
        crypto_blake2b_update(&ctx, info, info_len);
        crypto_blake2b_update(&ctx, &counter, 1u);
        crypto_blake2b_final(&ctx, block);
        block_len = sizeof(block);
        take = out_len - offset < block_len ? out_len - offset : block_len;
        memcpy(out + offset, block, take);
        offset += take;
    }
    crypto_wipe(prk, sizeof(prk));
    crypto_wipe(block, sizeof(block));
    crypto_wipe(&ctx, sizeof(ctx));
}

void kc_kdf_root(const uint8_t root[32],
                 const uint8_t dh[32],
                 uint8_t out_root[32],
                 uint8_t out_chain[32])
{
    uint8_t derived[64];

    kc_hkdf(root, 32u, dh, 32u, kc_hkdf_root_info,
            sizeof(kc_hkdf_root_info) - 1u, derived, sizeof(derived));
    memcpy(out_root, derived, 32u);
    memcpy(out_chain, derived + 32, 32u);
    crypto_wipe(derived, sizeof(derived));
}

void kc_kdf_chain(const uint8_t chain[32],
                  uint8_t out_chain[32],
                  uint8_t out_message[32])
{
    static const uint8_t message_tag = 0x01u;
    static const uint8_t chain_tag = 0x02u;
    uint8_t next[32];

    crypto_blake2b_keyed(out_message, 32u, chain, 32u, &message_tag, 1u);
    crypto_blake2b_keyed(next, 32u, chain, 32u, &chain_tag, 1u);
    memcpy(out_chain, next, 32u);
    crypto_wipe(next, sizeof(next));
}

void kc_kdf_message(const uint8_t message_key[32],
                    uint8_t out_key[32],
                    uint8_t out_nonce[12])
{
    uint8_t derived[44];

    kc_hkdf(NULL, 0u, message_key, 32u, kc_hkdf_message_info,
            sizeof(kc_hkdf_message_info) - 1u, derived, sizeof(derived));
    memcpy(out_key, derived, 32u);
    memcpy(out_nonce, derived + 32, 12u);
    crypto_wipe(derived, sizeof(derived));
}
