#include "kc_internal.h"

#include "kc_codec.h"
#include "kc_hkdf.h"
#include "kc_identity.h"
#include "monocypher.h"
#include <stdlib.h>
#include <string.h>

#define KC_GROUP_FIXED 160u
#define KC_GROUP_SKIP_SIZE 36u
#define KC_GROUP_SEND 1u
#define KC_GROUP_RECEIVE 2u
#define KC_GROUP_HEADER 64u
#define KC_GROUP_OVERHEAD (KC_GROUP_HEADER + 1u + KC_TAG_SIZE + 64u)

static const uint8_t kc_group_members_label[] = "promax-group-v1/members";
static const uint8_t kc_group_distribution_label[] = "promax-group-v1/distribution";
static const uint8_t kc_group_envelope_label[] = "promax-group-v1/envelope";
static const uint8_t kc_group_message_label[] = "promax-group-v1/message";
static const uint8_t kc_group_chain_label[] = "promax-group-v1/chain";
static const uint8_t kc_group_aead_label[] = "promax-group-v1/aead";
static const uint8_t kc_group_seed_label[] = "promax-group-v1/seed";
static const uint8_t kc_group_zero[32] = {0u};

static void kc_group_hash(uint8_t out[32], const uint8_t *label,
                          size_t label_len, const uint8_t *data, size_t len)
{
    crypto_blake2b_ctx hash;
    crypto_blake2b_init(&hash, 32u);
    crypto_blake2b_update(&hash, label, label_len);
    crypto_blake2b_update(&hash, data, len);
    crypto_blake2b_final(&hash, out);
    crypto_wipe(&hash, sizeof(hash));
}

static kc_status kc_group_members(int64_t group_id, int64_t sender_id,
    const uint8_t *members, size_t members_len, uint8_t digest[32],
    uint8_t sender_public[32])
{
    size_t count;
    size_t index;
    int found = 0;
    int64_t previous = 0;
    uint8_t group_bytes[8];
    crypto_blake2b_ctx hash;

    if (group_id == 0 || sender_id <= 0 || members == NULL ||
        members_len % KC_GROUP_MEMBER_SIZE != 0u) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    count = members_len / KC_GROUP_MEMBER_SIZE;
    if (count < 2u || count > KC_GROUP_MEMBERS_MAX) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    for (index = 0u; index < count; index++) {
        const uint8_t *member = members + index * KC_GROUP_MEMBER_SIZE;
        int64_t member_id = kc_load_i64(member);
        size_t other;
        if (member_id <= previous ||
            crypto_verify32(member + 8, kc_group_zero) == 0) {
            return KC_ERR_BAD_PEER;
        }
        for (other = 0u; other < index; other++) {
            if (crypto_verify32(member + 8,
                    members + other * KC_GROUP_MEMBER_SIZE + 8u) == 0) {
                return KC_ERR_BAD_PEER;
            }
        }
        if (member_id == sender_id) {
            memcpy(sender_public, member + 8, 32u);
            found = 1;
        }
        previous = member_id;
    }
    if (!found) {
        return KC_ERR_BAD_PEER;
    }
    kc_store_i64(group_bytes, group_id);
    crypto_blake2b_init(&hash, 32u);
    crypto_blake2b_update(&hash, kc_group_members_label,
                         sizeof(kc_group_members_label) - 1u);
    crypto_blake2b_update(&hash, group_bytes, sizeof(group_bytes));
    crypto_blake2b_update(&hash, members, members_len);
    crypto_blake2b_final(&hash, digest);
    crypto_wipe(&hash, sizeof(hash));
    return KC_OK;
}

kc_status kc_group_members_build(const int64_t *member_ids,
    const uint8_t *public_keys, size_t member_count, uint8_t *out_members,
    size_t members_cap, size_t *members_len)
{
    uint8_t members[KC_GROUP_MEMBERS_MAX * KC_GROUP_MEMBER_SIZE];
    uint8_t digest[32];
    uint8_t sender_public[32];
    size_t index;
    size_t len;
    kc_status status;
    if (member_ids == NULL || public_keys == NULL || members_len == NULL ||
        member_count < 2u || member_count > KC_GROUP_MEMBERS_MAX) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    len = member_count * KC_GROUP_MEMBER_SIZE;
    if (out_members == NULL || members_cap < len) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    for (index = 0u; index < member_count; index++) {
        kc_store_i64(members + index * KC_GROUP_MEMBER_SIZE, member_ids[index]);
        memcpy(members + index * KC_GROUP_MEMBER_SIZE + 8,
                 public_keys + index * KC_PUBLIC_KEY_SIZE, KC_PUBLIC_KEY_SIZE);
    }
    status = kc_group_members(1, member_ids[0], members, len, digest, sender_public);
    if (status == KC_OK) {
        memcpy(out_members, members, len);
        *members_len = len;
    }
    return status;
}

kc_status kc_group_members_digest(int64_t group_id,
    const uint8_t *members, size_t members_len, uint8_t *out_digest,
    size_t digest_cap, size_t *digest_len)
{
    uint8_t digest[32];
    uint8_t sender_public[32];
    kc_status status;
    if (members == NULL || members_len < KC_GROUP_MEMBER_SIZE ||
        digest_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_digest == NULL || digest_cap < sizeof(digest)) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_group_members(group_id, kc_load_i64(members), members,
                              members_len, digest, sender_public);
    if (status == KC_OK) {
        memcpy(out_digest, digest, sizeof(digest));
        *digest_len = sizeof(digest);
    }
    return status;
}

static kc_status kc_group_parse(const uint8_t *state, size_t len, uint8_t mode)
{
    uint32_t skipped;
    uint32_t next;
    uint32_t previous = 0u;
    size_t index;
    if (state == NULL || len < KC_GROUP_FIXED || len > KC_GROUP_STATE_MAX ||
        state[0] != 1u || state[1] != mode ||
        kc_load_i64(state + 2) == 0 || kc_load_u64(state + 10) == 0u ||
        kc_load_i64(state + 18) <= 0 ||
        crypto_verify32(state + 90, kc_group_zero) == 0) {
        return KC_ERR_BAD_STATE;
    }
    skipped = ((uint32_t)state[158] << 8u) | state[159];
    next = kc_load_u32(state + 154);
    if (skipped > KC_GROUP_MAX_SKIP ||
        len != KC_GROUP_FIXED + skipped * KC_GROUP_SKIP_SIZE ||
        (mode == KC_GROUP_SEND && skipped != 0u) ||
        (mode == KC_GROUP_RECEIVE &&
         crypto_verify32(state + 58, kc_group_zero) != 0)) {
        return KC_ERR_BAD_STATE;
    }
    for (index = 0u; index < skipped; index++) {
        uint32_t counter = kc_load_u32(state + KC_GROUP_FIXED +
                                      index * KC_GROUP_SKIP_SIZE);
        if (counter >= next || (index != 0u && counter <= previous)) {
            return KC_ERR_BAD_STATE;
        }
        previous = counter;
    }
    return KC_OK;
}

static void kc_group_state(uint8_t *state, uint8_t mode,
    const uint8_t *distribution, const uint8_t *identity)
{
    memset(state, 0, KC_GROUP_FIXED);
    state[0] = 1u;
    state[1] = mode;
    memcpy(state + 2, distribution + 4, 24u);
    memcpy(state + 26, distribution + 28, 32u);
    if (identity != NULL) {
        memcpy(state + 58, identity, 64u);
    } else {
        memcpy(state + 90, distribution + 60, 32u);
    }
    memcpy(state + 122, distribution + 92, 32u);
}

static kc_status kc_group_old(const uint8_t *old, size_t old_len,
    uint8_t mode, int64_t group_id, int64_t sender_id, uint64_t epoch,
    const uint8_t sender_public[32])
{
    kc_status status;
    uint64_t previous;
    if (old_len == 0u) {
        return KC_OK;
    }
    status = kc_group_parse(old, old_len, mode);
    if (status != KC_OK) {
        return status;
    }
    if (kc_load_i64(old + 2) != group_id ||
        kc_load_i64(old + 18) != sender_id ||
        crypto_verify32(old + 90, sender_public) != 0) {
        return KC_ERR_BAD_PEER;
    }
    previous = kc_load_u64(old + 10);
    if (epoch <= previous) {
        return KC_ERR_REPLAY;
    }
    if (mode == KC_GROUP_SEND &&
        (previous == UINT64_MAX || epoch != previous + 1u)) {
        return KC_ERR_BAD_STATE;
    }
    return KC_OK;
}

kc_status kc_group_sender_create(const uint8_t *identity,
    size_t identity_len, int64_t group_id, int64_t sender_id, uint64_t epoch,
    const uint8_t *members, size_t members_len, const uint8_t *random,
    size_t random_len, const uint8_t *old_state, size_t old_state_len,
    uint8_t *out_distribution, size_t distribution_cap,
    size_t *distribution_len, uint8_t *out_state, size_t state_cap,
    size_t *state_len)
{
    uint8_t distribution[KC_GROUP_DISTRIBUTION_SIZE];
    uint8_t digest[32];
    uint8_t sender_public[32];
    uint8_t restored_identity[64];
    uint8_t seed_info[sizeof(kc_group_seed_label) - 1u + 24u];
    size_t restored_len = 0u;
    kc_status status;

    if (identity == NULL || identity_len != KC_IDENTITY_SIZE ||
        random == NULL || random_len != 32u || epoch == 0u ||
        distribution_len == NULL || state_len == NULL ||
        (old_state == NULL && old_state_len != 0u) ||
        crypto_verify32(random, kc_group_zero) == 0) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (out_distribution == NULL || distribution_cap < sizeof(distribution) ||
        out_state == NULL || state_cap < KC_GROUP_FIXED) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_identity_create(identity, 32u, restored_identity,
                               sizeof(restored_identity), &restored_len);
    if (status != KC_OK ||
        crypto_verify32(restored_identity + 32, identity + 32) != 0) {
        crypto_wipe(restored_identity, sizeof(restored_identity));
        return KC_ERR_BAD_STATE;
    }
    crypto_wipe(restored_identity, sizeof(restored_identity));
    status = kc_group_members(group_id, sender_id, members, members_len,
                              digest, sender_public);
    if (status != KC_OK) {
        return status;
    }
    if (crypto_verify32(sender_public, identity + 32) != 0) {
        return KC_ERR_BAD_PEER;
    }
    status = kc_group_old(old_state, old_state_len, KC_GROUP_SEND, group_id,
                          sender_id, epoch, sender_public);
    if (status != KC_OK) {
        return status;
    }
    memcpy(distribution, "KG\x01\x01", 4u);
    kc_store_i64(distribution + 4, group_id);
    kc_store_u64(distribution + 12, epoch);
    kc_store_i64(distribution + 20, sender_id);
    memcpy(distribution + 28, digest, 32u);
    memcpy(distribution + 60, sender_public, 32u);
    memcpy(seed_info, kc_group_seed_label, sizeof(kc_group_seed_label) - 1u);
    memcpy(seed_info + sizeof(kc_group_seed_label) - 1u, distribution + 4, 24u);
    kc_hkdf(digest, sizeof(digest), random, random_len, seed_info,
             sizeof(seed_info), distribution + 92, 32u);
    kc_group_hash(digest, kc_group_distribution_label,
                   sizeof(kc_group_distribution_label) - 1u,
                   distribution, 124u);
    kc_identity_sign(identity, digest, sizeof(digest), distribution + 124);
    kc_group_state(out_state, KC_GROUP_SEND, distribution, identity);
    memcpy(out_distribution, distribution, sizeof(distribution));
    *distribution_len = sizeof(distribution);
    *state_len = KC_GROUP_FIXED;
    crypto_wipe(distribution, sizeof(distribution));
    crypto_wipe(digest, sizeof(digest));
    return KC_OK;
}

kc_status kc_group_receiver_import(int64_t group_id,
    int64_t sender_id, const uint8_t *members, size_t members_len,
    const uint8_t *distribution, size_t distribution_len,
    const uint8_t *old_state, size_t old_state_len,
    uint8_t *out_state, size_t state_cap, size_t *state_len)
{
    uint8_t digest[32];
    uint8_t sender_public[32];
    uint8_t new_state[KC_GROUP_FIXED];
    kc_status status;
    if (distribution == NULL || state_len == NULL ||
        (old_state == NULL && old_state_len != 0u)) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (distribution_len != KC_GROUP_DISTRIBUTION_SIZE ||
        memcmp(distribution, "KG\x01\x01", 4u) != 0 ||
        kc_load_u64(distribution + 12) == 0u) {
        return KC_ERR_MALFORMED;
    }
    if (out_state == NULL || state_cap < KC_GROUP_FIXED) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_group_members(group_id, sender_id, members, members_len,
                              digest, sender_public);
    if (status != KC_OK) {
        return status;
    }
    if (kc_load_i64(distribution + 4) != group_id ||
        kc_load_i64(distribution + 20) != sender_id ||
        crypto_verify32(distribution + 28, digest) != 0 ||
        crypto_verify32(distribution + 60, sender_public) != 0) {
        return KC_ERR_BAD_PEER;
    }
    kc_group_hash(digest, kc_group_distribution_label,
                   sizeof(kc_group_distribution_label) - 1u,
                   distribution, 124u);
    if (!kc_identity_verify(sender_public, digest, sizeof(digest),
                             distribution + 124)) {
        return KC_ERR_BAD_SIGNATURE;
    }
    status = kc_group_old(old_state, old_state_len, KC_GROUP_RECEIVE, group_id,
        sender_id, kc_load_u64(distribution + 12), sender_public);
    if (status != KC_OK) {
        return status;
    }
    kc_group_state(new_state, KC_GROUP_RECEIVE, distribution, NULL);
    memcpy(out_state, new_state, sizeof(new_state));
    *state_len = sizeof(new_state);
    crypto_wipe(new_state, sizeof(new_state));
    return KC_OK;
}

static void kc_group_step(uint8_t chain[32], uint8_t message_key[32])
{
    uint8_t next[32];
    crypto_blake2b_keyed(message_key, 32u, chain, 32u,
        kc_group_message_label, sizeof(kc_group_message_label) - 1u);
    crypto_blake2b_keyed(next, 32u, chain, 32u,
        kc_group_chain_label, sizeof(kc_group_chain_label) - 1u);
    memcpy(chain, next, sizeof(next));
    crypto_wipe(next, sizeof(next));
}

static void kc_group_expand(const uint8_t message_key[32],
                             uint8_t key[32], uint8_t nonce[12])
{
    uint8_t expanded[44];
    kc_hkdf(NULL, 0u, message_key, 32u, kc_group_aead_label,
             sizeof(kc_group_aead_label) - 1u, expanded, sizeof(expanded));
    memcpy(key, expanded, 32u);
    memcpy(nonce, expanded + 32, 12u);
    crypto_wipe(expanded, sizeof(expanded));
}

size_t kc_group_encrypt_bound(size_t plaintext_len)
{
    return plaintext_len > KC_GROUP_PLAINTEXT_MAX ? 0u :
        plaintext_len + KC_GROUP_OVERHEAD;
}

size_t kc_group_decrypt_bound(size_t envelope_len)
{
    return envelope_len < KC_GROUP_OVERHEAD ||
        envelope_len > KC_GROUP_PLAINTEXT_MAX + KC_GROUP_OVERHEAD ? 0u :
        envelope_len - KC_GROUP_OVERHEAD;
}

kc_status kc_group_encrypt(const uint8_t *state, size_t state_len,
    uint8_t content_type, const uint8_t *plaintext, size_t plaintext_len,
    uint8_t *out_envelope, size_t envelope_cap, size_t *envelope_len,
    uint8_t *out_state, size_t state_cap, size_t *state_out_len)
{
    uint8_t next_state[KC_GROUP_FIXED];
    uint8_t message_key[32];
    uint8_t key[32];
    uint8_t nonce[12];
    uint8_t digest[32];
    uint8_t *envelope;
    size_t bound = kc_group_encrypt_bound(plaintext_len);
    size_t sealed_len = 0u;
    uint32_t counter;
    kc_status status;
    if (envelope_len == NULL || state_out_len == NULL ||
        (plaintext == NULL && plaintext_len != 0u) ||
        content_type < KC_CONTENT_TEXT || content_type > KC_CONTENT_CONTROL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (bound == 0u) {
        return KC_ERR_TOO_LONG;
    }
    if (content_type == KC_CONTENT_TEXT &&
        !kc_utf8_valid(plaintext, plaintext_len)) {
        return KC_ERR_MALFORMED;
    }
    if (out_envelope == NULL || envelope_cap < bound || out_state == NULL ||
        state_cap < KC_GROUP_FIXED) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_group_parse(state, state_len, KC_GROUP_SEND);
    if (status != KC_OK) {
        return status;
    }
    counter = kc_load_u32(state + 154);
    if (counter == UINT32_MAX) {
        return KC_ERR_BAD_STATE;
    }
    envelope = (uint8_t *)malloc(bound);
    if (envelope == NULL) {
        return KC_ERR_OUT_OF_MEMORY;
    }
    memcpy(next_state, state, sizeof(next_state));
    memcpy(envelope, "KG\x01\x02", 4u);
    memcpy(envelope + 4, state + 2, 24u);
    memcpy(envelope + 28, state + 26, 32u);
    kc_store_u32(envelope + 60, counter);
    envelope[64] = content_type;
    if (plaintext_len != 0u) {
        memcpy(envelope + 65, plaintext, plaintext_len);
    }
    kc_group_step(next_state + 122, message_key);
    kc_group_expand(message_key, key, nonce);
    status = kc_seal(envelope + 64, plaintext_len + 1u, key, sizeof(key),
        nonce, sizeof(nonce), envelope, KC_GROUP_HEADER, envelope + 64,
        plaintext_len + 1u + KC_TAG_SIZE, &sealed_len);
    if (status == KC_OK) {
        kc_group_hash(digest, kc_group_envelope_label,
            sizeof(kc_group_envelope_label) - 1u, envelope, bound - 64u);
        kc_identity_sign(state + 58, digest, sizeof(digest),
                           envelope + bound - 64u);
        kc_store_u32(next_state + 154, counter + 1u);
        memcpy(out_envelope, envelope, bound);
        memcpy(out_state, next_state, sizeof(next_state));
        *envelope_len = bound;
        *state_out_len = sizeof(next_state);
    }
    crypto_wipe(envelope, bound);
    free(envelope);
    crypto_wipe(next_state, sizeof(next_state));
    crypto_wipe(message_key, sizeof(message_key));
    crypto_wipe(key, sizeof(key));
    crypto_wipe(nonce, sizeof(nonce));
    return status;
}

static kc_status kc_group_receive_key(uint8_t *state, uint32_t counter,
    uint8_t message_key[32], size_t *state_len)
{
    uint32_t next = kc_load_u32(state + 154);
    uint32_t skipped = ((uint32_t)state[158] << 8u) | state[159];
    size_t index;
    if (counter == UINT32_MAX) {
        return KC_ERR_BAD_STATE;
    }
    if (counter < next) {
        for (index = 0u; index < skipped; index++) {
            uint8_t *entry = state + KC_GROUP_FIXED + index * KC_GROUP_SKIP_SIZE;
            if (kc_load_u32(entry) == counter) {
                memcpy(message_key, entry + 4, 32u);
                memmove(entry, entry + KC_GROUP_SKIP_SIZE,
                    (skipped - index - 1u) * KC_GROUP_SKIP_SIZE);
                skipped--;
                state[158] = (uint8_t)(skipped >> 8u);
                state[159] = (uint8_t)skipped;
                *state_len = KC_GROUP_FIXED + skipped * KC_GROUP_SKIP_SIZE;
                crypto_wipe(state + *state_len, KC_GROUP_SKIP_SIZE);
                return KC_OK;
            }
        }
        return KC_ERR_REPLAY;
    }
    if (counter - next > KC_GROUP_MAX_SKIP ||
        skipped + counter - next > KC_GROUP_MAX_SKIP) {
        return KC_ERR_TOO_MANY_SKIPPED;
    }
    while (next < counter) {
        uint8_t *entry = state + KC_GROUP_FIXED + skipped * KC_GROUP_SKIP_SIZE;
        kc_store_u32(entry, next);
        kc_group_step(state + 122, entry + 4);
        skipped++;
        next++;
    }
    kc_group_step(state + 122, message_key);
    kc_store_u32(state + 154, counter + 1u);
    state[158] = (uint8_t)(skipped >> 8u);
    state[159] = (uint8_t)skipped;
    *state_len = KC_GROUP_FIXED + skipped * KC_GROUP_SKIP_SIZE;
    return KC_OK;
}

kc_status kc_group_decrypt(const uint8_t *state, size_t state_len,
    const uint8_t *envelope, size_t envelope_len, uint8_t *out_content_type,
    uint8_t *out_plaintext, size_t plaintext_cap, size_t *plaintext_len,
    uint8_t *out_state, size_t state_cap, size_t *state_out_len)
{
    uint8_t digest[32];
    uint8_t message_key[32];
    uint8_t key[32];
    uint8_t nonce[12];
    uint8_t *next_state;
    uint8_t *body;
    size_t next_len = state_len;
    size_t body_len = 0u;
    size_t bound;
    kc_status status;
    if (envelope == NULL || plaintext_len == NULL || out_content_type == NULL ||
        state_out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    if (envelope_len < KC_GROUP_OVERHEAD ||
        envelope_len > KC_GROUP_OVERHEAD + KC_GROUP_PLAINTEXT_MAX ||
        memcmp(envelope, "KG\x01\x02", 4u) != 0) {
        return KC_ERR_MALFORMED;
    }
    bound = kc_group_decrypt_bound(envelope_len);
    if ((out_plaintext == NULL && bound != 0u) || plaintext_cap < bound ||
        out_state == NULL || state_cap < KC_GROUP_FIXED) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    status = kc_group_parse(state, state_len, KC_GROUP_RECEIVE);
    if (status != KC_OK) {
        return status;
    }
    if (memcmp(envelope + 4, state + 2, 24u) != 0 ||
        crypto_verify32(envelope + 28, state + 26) != 0) {
        return KC_ERR_BAD_PEER;
    }
    kc_group_hash(digest, kc_group_envelope_label,
        sizeof(kc_group_envelope_label) - 1u, envelope, envelope_len - 64u);
    if (!kc_identity_verify(state + 90, digest, sizeof(digest),
                             envelope + envelope_len - 64u)) {
        return KC_ERR_BAD_SIGNATURE;
    }
    next_state = (uint8_t *)calloc(1u, KC_GROUP_STATE_MAX);
    body = (uint8_t *)malloc(bound + 1u);
    if (next_state == NULL || body == NULL) {
        free(next_state);
        free(body);
        return KC_ERR_OUT_OF_MEMORY;
    }
    memcpy(next_state, state, state_len);
    status = kc_group_receive_key(next_state, kc_load_u32(envelope + 60),
                                   message_key, &next_len);
    if (status == KC_OK && state_cap < next_len) {
        status = KC_ERR_BUFFER_TOO_SMALL;
    }
    if (status == KC_OK) {
        kc_group_expand(message_key, key, nonce);
        status = kc_open(envelope + 64, bound + 1u + KC_TAG_SIZE, key,
            sizeof(key), nonce, envelope, KC_GROUP_HEADER, body, bound + 1u,
            &body_len);
    }
    if (status == KC_OK && (body_len != bound + 1u ||
        body[0] < KC_CONTENT_TEXT || body[0] > KC_CONTENT_CONTROL)) {
        status = KC_ERR_MALFORMED;
    }
    if (status == KC_OK && body[0] == KC_CONTENT_TEXT &&
        !kc_utf8_valid(body + 1, bound)) {
        status = KC_ERR_MALFORMED;
    }
    if (status == KC_OK) {
        if (bound != 0u) {
            memcpy(out_plaintext, body + 1, bound);
        }
        memcpy(out_state, next_state, next_len);
        *out_content_type = body[0];
        *plaintext_len = bound;
        *state_out_len = next_len;
    }
    crypto_wipe(next_state, KC_GROUP_STATE_MAX);
    free(next_state);
    crypto_wipe(body, bound + 1u);
    free(body);
    crypto_wipe(message_key, sizeof(message_key));
    crypto_wipe(key, sizeof(key));
    crypto_wipe(nonce, sizeof(nonce));
    return status;
}
