#include "promax_crypto.h"
#include "kc_codec.h"
#include "kc_identity.h"
#include "monocypher.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int kc_group_test_failures;

static void group_expect(int condition, const char *name)
{
    if (!condition) {
        fprintf(stderr, "group: %s\n", name);
        kc_group_test_failures++;
    }
}

typedef struct {
    uint8_t identities[3][KC_IDENTITY_SIZE];
    uint8_t members[3u * KC_GROUP_MEMBER_SIZE];
    uint8_t distribution[KC_GROUP_DISTRIBUTION_SIZE];
    uint8_t sender[KC_GROUP_STATE_MAX];
    uint8_t receiver[KC_GROUP_STATE_MAX];
    size_t sender_len;
    size_t receiver_len;
    uint8_t random[32];
} group_fixture;

static void group_fixture_init(group_fixture *fixture)
{
    size_t member;
    size_t index;
    size_t len = 0u;
    memset(fixture, 0, sizeof(*fixture));
    for (member = 0u; member < 3u; member++) {
        uint8_t seed[32];
        for (index = 0u; index < sizeof(seed); index++) {
            seed[index] = (uint8_t)(index + 17u + member * 37u);
            fixture->random[index] = (uint8_t)(index + 71u);
        }
        group_expect(kc_identity_create(seed, sizeof(seed),
            fixture->identities[member], KC_IDENTITY_SIZE, &len) == KC_OK,
            "fixture identity");
        kc_store_i64(fixture->members + member * KC_GROUP_MEMBER_SIZE,
                       10001 + (int64_t)member);
        memcpy(fixture->members + member * KC_GROUP_MEMBER_SIZE + 8,
            fixture->identities[member] + 32, 32u);
    }
    group_expect(kc_group_sender_create(fixture->identities[0],
        KC_IDENTITY_SIZE, -20001, 10001, 1u, fixture->members,
        2u * KC_GROUP_MEMBER_SIZE, fixture->random, 32u, NULL, 0u,
        fixture->distribution, sizeof(fixture->distribution), &len,
        fixture->sender, sizeof(fixture->sender), &fixture->sender_len) == KC_OK,
        "fixture sender");
    group_expect(len == KC_GROUP_DISTRIBUTION_SIZE, "distribution length");
    group_expect(kc_group_receiver_import(-20001, 10001, fixture->members,
        2u * KC_GROUP_MEMBER_SIZE, fixture->distribution,
        sizeof(fixture->distribution), NULL, 0u, fixture->receiver,
        sizeof(fixture->receiver), &fixture->receiver_len) == KC_OK,
        "fixture receiver");
}

static kc_status group_encrypt(group_fixture *fixture, uint8_t *envelope,
    size_t cap, size_t *len)
{
    static const uint8_t payload[] = "synthetic group payload";
    return kc_group_encrypt(fixture->sender, fixture->sender_len,
        KC_CONTENT_TEXT, payload, sizeof(payload) - 1u, envelope, cap, len,
        fixture->sender, sizeof(fixture->sender), &fixture->sender_len);
}

static kc_status group_decrypt(group_fixture *fixture,
    const uint8_t *envelope, size_t len)
{
    uint8_t plaintext[128];
    uint8_t type = 0u;
    size_t plaintext_len = 0u;
    return kc_group_decrypt(fixture->receiver, fixture->receiver_len,
        envelope, len, &type, plaintext, sizeof(plaintext), &plaintext_len,
        fixture->receiver, sizeof(fixture->receiver), &fixture->receiver_len);
}

static void test_group_roundtrip(void)
{
    group_fixture fixture;
    uint8_t envelope[256];
    uint8_t plaintext[128];
    uint8_t type;
    uint8_t payload[] = {0u, 1u, 65u, 127u};
    size_t len = 0u;
    size_t plaintext_len = 0u;
    group_fixture_init(&fixture);
    for (type = KC_CONTENT_TEXT; type <= KC_CONTENT_CONTROL; type++) {
        uint8_t found_type = 0u;
        group_expect(kc_group_encrypt(fixture.sender, fixture.sender_len,
            type, payload, sizeof(payload), envelope, sizeof(envelope), &len,
            fixture.sender, sizeof(fixture.sender), &fixture.sender_len) == KC_OK,
            "encrypt all content types");
        group_expect(len == kc_group_encrypt_bound(sizeof(payload)),
            "encrypt bound");
        group_expect(kc_group_decrypt(fixture.receiver, fixture.receiver_len,
            envelope, len, &found_type, plaintext, sizeof(plaintext),
            &plaintext_len, fixture.receiver, sizeof(fixture.receiver),
            &fixture.receiver_len) == KC_OK, "decrypt all content types");
        group_expect(found_type == type && plaintext_len == sizeof(payload) &&
            memcmp(plaintext, payload, sizeof(payload)) == 0, "roundtrip payload");
        group_expect(group_decrypt(&fixture, envelope, len) == KC_ERR_REPLAY,
            "ordered replay rejected");
    }
    group_expect(kc_group_encrypt(fixture.sender, fixture.sender_len,
        KC_CONTENT_CONTROL, NULL, 0u, envelope, sizeof(envelope), &len,
        fixture.sender, sizeof(fixture.sender), &fixture.sender_len) == KC_OK,
        "empty control encrypt");
    group_expect(kc_group_decrypt(fixture.receiver, fixture.receiver_len,
        envelope, len, &type, NULL, 0u, &plaintext_len,
        fixture.receiver, sizeof(fixture.receiver), &fixture.receiver_len) == KC_OK,
        "empty control decrypt");
    group_expect(plaintext_len == 0u && type == KC_CONTENT_CONTROL,
        "empty control payload");
}

static void test_group_out_of_order(void)
{
    group_fixture fixture;
    uint8_t envelopes[3][256];
    size_t lengths[3];
    size_t index;
    group_fixture_init(&fixture);
    for (index = 0u; index < 3u; index++) {
        group_expect(group_encrypt(&fixture, envelopes[index],
            sizeof(envelopes[index]), &lengths[index]) == KC_OK,
            "out-of-order encrypt");
    }
    group_expect(group_decrypt(&fixture, envelopes[2], lengths[2]) == KC_OK,
        "future counter accepted");
    group_expect(group_decrypt(&fixture, envelopes[0], lengths[0]) == KC_OK,
        "first skipped key accepted");
    group_expect(group_decrypt(&fixture, envelopes[0], lengths[0]) == KC_ERR_REPLAY,
        "skipped key replay rejected");
    group_expect(group_decrypt(&fixture, envelopes[1], lengths[1]) == KC_OK,
        "second skipped key accepted");
    group_expect(fixture.receiver_len == 160u, "skipped keys removed");
}

static void group_resign(uint8_t *envelope, size_t len,
                           const uint8_t identity[64])
{
    static const uint8_t label[] = "promax-group-v1/envelope";
    crypto_blake2b_ctx hash;
    uint8_t digest[32];
    crypto_blake2b_init(&hash, sizeof(digest));
    crypto_blake2b_update(&hash, label, sizeof(label) - 1u);
    crypto_blake2b_update(&hash, envelope, len - 64u);
    crypto_blake2b_final(&hash, digest);
    kc_identity_sign(identity, digest, sizeof(digest), envelope + len - 64u);
}

static void test_group_authentication(void)
{
    group_fixture fixture;
    uint8_t envelope[256];
    uint8_t modified[256];
    uint8_t before[KC_GROUP_STATE_MAX];
    size_t len = 0u;
    size_t index;
    group_fixture_init(&fixture);
    group_expect(group_encrypt(&fixture, envelope, sizeof(envelope), &len) == KC_OK,
        "authentication encrypt");
    memcpy(before, fixture.receiver, fixture.receiver_len);
    for (index = 0u; index < len; index++) {
        kc_status status;
        memcpy(modified, envelope, len);
        modified[index] ^= 1u;
        status = group_decrypt(&fixture, modified, len);
        group_expect(status != KC_OK, "every envelope byte authenticated");
        group_expect(fixture.receiver_len == 160u &&
            memcmp(fixture.receiver, before, fixture.receiver_len) == 0,
            "tamper leaves receiver unchanged");
    }
    memcpy(modified, envelope, len);
    group_resign(modified, len, fixture.identities[1]);
    group_expect(group_decrypt(&fixture, modified, len) == KC_ERR_BAD_SIGNATURE,
        "member knowing chain cannot impersonate sender");
    memcpy(modified, envelope, len);
    modified[65] ^= 1u;
    group_resign(modified, len, fixture.identities[0]);
    group_expect(group_decrypt(&fixture, modified, len) == KC_ERR_WRONG_KEY,
        "valid signature cannot bypass AEAD");
    group_expect(memcmp(fixture.receiver, before, fixture.receiver_len) == 0,
        "AEAD failure does not consume chain");
    group_expect(group_decrypt(&fixture, envelope, len) == KC_OK,
        "valid envelope survives previous failures");
}

static void test_group_membership_rotation(void)
{
    group_fixture fixture;
    uint8_t old_envelope[256];
    uint8_t new_envelope[256];
    uint8_t old_receiver[KC_GROUP_STATE_MAX];
    uint8_t distribution[KC_GROUP_DISTRIBUTION_SIZE];
    uint8_t new_receiver[KC_GROUP_STATE_MAX];
    size_t old_len = 0u;
    size_t new_len = 0u;
    size_t distribution_len = 0u;
    size_t new_receiver_len = 0u;
    size_t old_receiver_len;
    uint64_t epoch;
    group_fixture_init(&fixture);
    group_expect(group_encrypt(&fixture, old_envelope, sizeof(old_envelope),
        &old_len) == KC_OK, "old epoch encrypt");
    old_receiver_len = fixture.receiver_len;
    memcpy(old_receiver, fixture.receiver, old_receiver_len);
    for (epoch = 2u; epoch <= 3u; epoch++) {
        size_t members_len = (epoch == 2u ? 3u : 2u) * KC_GROUP_MEMBER_SIZE;
        group_expect(kc_group_sender_create(fixture.identities[0],
            KC_IDENTITY_SIZE, -20001, 10001, epoch, fixture.members, members_len,
            fixture.random, sizeof(fixture.random), fixture.sender,
            fixture.sender_len, distribution, sizeof(distribution),
            &distribution_len, fixture.sender, sizeof(fixture.sender),
            &fixture.sender_len) == KC_OK, "join and leave rotate sender key");
        group_expect(kc_group_receiver_import(-20001, 10001, fixture.members,
            members_len, distribution, distribution_len, fixture.receiver,
            fixture.receiver_len, new_receiver, sizeof(new_receiver),
            &new_receiver_len) == KC_OK, "join and leave import epoch");
        group_expect(memcmp(distribution + 92, fixture.distribution + 92,
            32u) != 0, "rotation changes chain seed");
        memcpy(fixture.receiver, new_receiver, new_receiver_len);
        fixture.receiver_len = new_receiver_len;
        group_expect(kc_group_receiver_import(-20001, 10001, fixture.members,
            members_len, distribution, distribution_len, fixture.receiver,
            fixture.receiver_len, new_receiver, sizeof(new_receiver),
            &new_receiver_len) == KC_ERR_REPLAY, "distribution rollback rejected");
        group_expect(group_decrypt(&fixture, old_envelope, old_len) == KC_ERR_BAD_PEER,
            "new epoch rejects old message");
        group_expect(group_encrypt(&fixture, new_envelope, sizeof(new_envelope),
            &new_len) == KC_OK, "new epoch encrypt");
        memcpy(new_receiver, fixture.receiver, fixture.receiver_len);
        new_receiver_len = fixture.receiver_len;
        memcpy(fixture.receiver, old_receiver, old_receiver_len);
        fixture.receiver_len = old_receiver_len;
        group_expect(group_decrypt(&fixture, new_envelope, new_len) == KC_ERR_BAD_PEER,
            "removed member old state cannot decrypt new epoch");
        memcpy(fixture.receiver, new_receiver, new_receiver_len);
        fixture.receiver_len = new_receiver_len;
        group_expect(group_decrypt(&fixture, new_envelope, new_len) == KC_OK,
            "new epoch message decrypts");
    }
    group_expect(kc_group_receiver_import(-20001, 10001, fixture.members,
        3u * KC_GROUP_MEMBER_SIZE, distribution, distribution_len, NULL, 0u,
        new_receiver, sizeof(new_receiver), &new_receiver_len) == KC_ERR_BAD_PEER,
        "distribution cannot substitute membership");
}

static void test_group_cross_epoch_replay(void)
{
    group_fixture fixture;
    uint8_t rotated_distribution[KC_GROUP_DISTRIBUTION_SIZE];
    uint8_t rotated_sender[KC_GROUP_STATE_MAX];
    uint8_t rotated_receiver[KC_GROUP_STATE_MAX];
    uint8_t output[KC_GROUP_STATE_MAX];
    uint8_t before[KC_GROUP_STATE_MAX];
    size_t distribution_len = 0u;
    size_t sender_len = 0u;
    size_t receiver_len = 0u;
    size_t output_len = 123u;
    group_fixture_init(&fixture);
    group_expect(kc_group_sender_create(fixture.identities[0], KC_IDENTITY_SIZE,
        -20001, 10001, 2u, fixture.members, 3u * KC_GROUP_MEMBER_SIZE,
        fixture.random, sizeof(fixture.random), fixture.sender, fixture.sender_len,
        rotated_distribution, sizeof(rotated_distribution), &distribution_len,
        rotated_sender, sizeof(rotated_sender), &sender_len) == KC_OK,
        "create signed rotated distribution");
    group_expect(kc_group_receiver_import(-20001, 10001, fixture.members,
        3u * KC_GROUP_MEMBER_SIZE, rotated_distribution, distribution_len,
        fixture.receiver, fixture.receiver_len, rotated_receiver,
        sizeof(rotated_receiver), &receiver_len) == KC_OK,
        "import signed rotated distribution");
    memset(output, 0xa5, sizeof(output));
    memcpy(before, output, sizeof(output));
    group_expect(kc_group_receiver_import(-20001, 10001, fixture.members,
        2u * KC_GROUP_MEMBER_SIZE, fixture.distribution,
        sizeof(fixture.distribution), rotated_receiver, receiver_len, output,
        sizeof(output), &output_len) == KC_ERR_REPLAY,
        "old signed distribution rejected after newer epoch");
    group_expect(output_len == 123u && memcmp(before, output, sizeof(output)) == 0,
        "rejected epoch replay leaves output untouched");
    group_expect(kc_group_receiver_import(-20001, 10001, fixture.members,
        2u * KC_GROUP_MEMBER_SIZE, rotated_distribution, distribution_len,
        fixture.receiver, fixture.receiver_len, output, sizeof(output),
        &output_len) == KC_ERR_BAD_PEER,
        "signed rotated distribution rejects substituted membership");
    group_expect(output_len == 123u && memcmp(before, output, sizeof(output)) == 0,
        "rejected membership substitution leaves output untouched");
}

static void test_group_distribution_validation(void)
{
    group_fixture fixture;
    uint8_t modified[KC_GROUP_DISTRIBUTION_SIZE];
    uint8_t output[KC_GROUP_STATE_MAX];
    uint8_t bad_members[3u * KC_GROUP_MEMBER_SIZE];
    size_t output_len = 0u;
    size_t index;
    group_fixture_init(&fixture);
    for (index = 0u; index < sizeof(modified); index++) {
        memcpy(modified, fixture.distribution, sizeof(modified));
        modified[index] ^= 1u;
        group_expect(kc_group_receiver_import(-20001, 10001, fixture.members,
            2u * KC_GROUP_MEMBER_SIZE, modified, sizeof(modified), NULL, 0u,
            output, sizeof(output), &output_len) != KC_OK,
            "every distribution byte authenticated");
    }
    for (index = 0u; index < sizeof(modified); index++) {
        group_expect(kc_group_receiver_import(-20001, 10001, fixture.members,
            2u * KC_GROUP_MEMBER_SIZE, fixture.distribution, index, NULL, 0u,
            output, sizeof(output), &output_len) == KC_ERR_MALFORMED,
            "truncated distribution rejected");
    }
    memcpy(bad_members, fixture.members, sizeof(bad_members));
    memcpy(bad_members + KC_GROUP_MEMBER_SIZE + 8,
        bad_members + 8, KC_PUBLIC_KEY_SIZE);
    group_expect(kc_group_receiver_import(-20001, 10001, bad_members,
        2u * KC_GROUP_MEMBER_SIZE, fixture.distribution,
        sizeof(fixture.distribution), NULL, 0u, output, sizeof(output),
        &output_len) == KC_ERR_BAD_PEER, "duplicate public keys rejected");
    memcpy(bad_members, fixture.members, sizeof(bad_members));
    memcpy(bad_members + KC_GROUP_MEMBER_SIZE, bad_members, 8u);
    group_expect(kc_group_receiver_import(-20001, 10001, bad_members,
        2u * KC_GROUP_MEMBER_SIZE, fixture.distribution,
        sizeof(fixture.distribution), NULL, 0u, output, sizeof(output),
        &output_len) == KC_ERR_BAD_PEER, "duplicate IDs rejected");
    group_expect(kc_group_sender_create(fixture.identities[1],
        KC_IDENTITY_SIZE, -20001, 10001, 2u, fixture.members,
        2u * KC_GROUP_MEMBER_SIZE, fixture.random, sizeof(fixture.random),
        fixture.sender, fixture.sender_len, modified, sizeof(modified),
        &output_len, output, sizeof(output), &output_len) == KC_ERR_BAD_PEER,
        "sender identity must match member");
}

static void test_group_bounded_skip(void)
{
    group_fixture fixture;
    uint8_t first[256];
    uint8_t envelope[256];
    uint8_t too_far[256];
    size_t first_len = 0u;
    size_t len = 0u;
    size_t too_far_len = 0u;
    size_t index;
    group_fixture_init(&fixture);
    group_expect(group_encrypt(&fixture, first, sizeof(first), &first_len) == KC_OK,
        "bounded skip first encrypt");
    for (index = 1u; index <= KC_GROUP_MAX_SKIP + 1u; index++) {
        group_expect(group_encrypt(&fixture, envelope, sizeof(envelope), &len)
            == KC_OK, "bounded skip encrypt");
        if (index == KC_GROUP_MAX_SKIP) {
            memcpy(too_far, envelope, len);
            too_far_len = len;
        }
    }
    group_expect(group_decrypt(&fixture, envelope, len) == KC_ERR_TOO_MANY_SKIPPED,
        "excessive counter gap rejected");
    group_expect(group_decrypt(&fixture, too_far, too_far_len) == KC_OK,
        "maximum skipped window accepted");
    group_expect(fixture.receiver_len == KC_GROUP_STATE_MAX,
        "receiver state bounded to maximum");
    group_expect(group_decrypt(&fixture, first, first_len) == KC_OK,
        "oldest retained key accepted at maximum window");
    group_expect(group_decrypt(&fixture, first, first_len) == KC_ERR_REPLAY,
        "maximum window replay rejected");
}

static void test_group_capacity_and_malformed(void)
{
    group_fixture fixture;
    uint8_t envelope[256];
    uint8_t before[KC_GROUP_STATE_MAX];
    uint8_t output[256];
    uint8_t type = 0u;
    size_t len = 0u;
    size_t output_len = 123u;
    size_t state_len = 456u;
    size_t index;
    group_fixture_init(&fixture);
    memcpy(before, fixture.sender, fixture.sender_len);
    group_expect(group_encrypt(&fixture, envelope, 1u, &len) ==
        KC_ERR_BUFFER_TOO_SMALL, "small encryption buffer rejected");
    group_expect(memcmp(before, fixture.sender, fixture.sender_len) == 0,
        "small encryption buffer leaves send state unchanged");
    group_expect(group_encrypt(&fixture, envelope, sizeof(envelope), &len) == KC_OK,
        "capacity encrypt");
    memcpy(before, fixture.receiver, fixture.receiver_len);
    group_expect(kc_group_decrypt(fixture.receiver, fixture.receiver_len,
        envelope, len, &type, output, 1u, &output_len, fixture.receiver,
        sizeof(fixture.receiver), &state_len) == KC_ERR_BUFFER_TOO_SMALL,
        "small plaintext buffer rejected");
    group_expect(memcmp(before, fixture.receiver, fixture.receiver_len) == 0 &&
        output_len == 123u && state_len == 456u,
        "capacity error leaves state and lengths unchanged");
    for (index = 0u; index < len; index++) {
        group_expect(group_decrypt(&fixture, envelope, index) != KC_OK,
            "truncated envelope rejected");
    }
    fixture.receiver[158] = 255u;
    fixture.receiver[159] = 255u;
    group_expect(group_decrypt(&fixture, envelope, len) == KC_ERR_BAD_STATE,
        "oversized skipped count rejected");
    group_expect(kc_group_encrypt_bound(SIZE_MAX) == 0u &&
        kc_group_decrypt_bound(SIZE_MAX) == 0u,
        "size overflow bounds rejected");
}

static void test_group_members_build(void)
{
    group_fixture fixture;
    int64_t ids[3] = {10001, 10002, 10003};
    uint8_t keys[3u * KC_PUBLIC_KEY_SIZE];
    uint8_t manifest[3u * KC_GROUP_MEMBER_SIZE];
    uint8_t before[sizeof(manifest)];
    size_t len = 0u;
    size_t index;
    group_fixture_init(&fixture);
    for (index = 0u; index < 3u; index++) {
        memcpy(keys + index * KC_PUBLIC_KEY_SIZE,
            fixture.identities[index] + 32, KC_PUBLIC_KEY_SIZE);
    }
    group_expect(kc_group_members_build(ids, keys, 3u, manifest,
        sizeof(manifest), &len) == KC_OK, "typed manifest builds");
    group_expect(len == sizeof(manifest) &&
        memcmp(manifest, fixture.members, sizeof(manifest)) == 0,
        "typed manifest exact native format");
    memcpy(before, manifest, sizeof(manifest));
    ids[1] = ids[0];
    group_expect(kc_group_members_build(ids, keys, 3u, manifest,
        sizeof(manifest), &len) == KC_ERR_BAD_PEER,
        "typed manifest duplicate IDs rejected");
    group_expect(memcmp(before, manifest, sizeof(manifest)) == 0,
        "invalid typed manifest preserves output");
    group_expect(kc_group_members_build(ids, keys, SIZE_MAX, manifest,
        sizeof(manifest), &len) == KC_ERR_INVALID_ARGUMENT,
        "typed manifest count overflow rejected");
}

static void test_group_payload_limits(void)
{
    group_fixture fixture;
    uint8_t *plaintext = (uint8_t *)malloc(KC_GROUP_PLAINTEXT_MAX + 1u);
    uint8_t *envelope = (uint8_t *)malloc(
        kc_group_encrypt_bound(KC_GROUP_PLAINTEXT_MAX));
    uint8_t *opened = (uint8_t *)malloc(KC_GROUP_PLAINTEXT_MAX);
    size_t len = 0u;
    size_t opened_len = 0u;
    uint8_t content_type = 0u;
    group_fixture_init(&fixture);
    group_expect(plaintext != NULL && envelope != NULL && opened != NULL,
        "payload boundary allocation");
    if (plaintext == NULL || envelope == NULL || opened == NULL) {
        free(plaintext);
        free(envelope);
        free(opened);
        return;
    }
    memset(plaintext, 'A', KC_GROUP_PLAINTEXT_MAX + 1u);
    group_expect(kc_group_encrypt(fixture.sender, fixture.sender_len,
        KC_CONTENT_TEXT, plaintext, KC_GROUP_PLAINTEXT_MAX + 1u, envelope,
        kc_group_encrypt_bound(KC_GROUP_PLAINTEXT_MAX), &len,
        fixture.sender, sizeof(fixture.sender), &fixture.sender_len) ==
        KC_ERR_TOO_LONG, "oversized payload rejected");
    group_expect(kc_group_encrypt(fixture.sender, fixture.sender_len,
        KC_CONTENT_TEXT, plaintext, KC_GROUP_PLAINTEXT_MAX, envelope,
        kc_group_encrypt_bound(KC_GROUP_PLAINTEXT_MAX), &len,
        fixture.sender, sizeof(fixture.sender), &fixture.sender_len) == KC_OK,
        "maximum payload encrypts");
    group_expect(kc_group_decrypt(fixture.receiver, fixture.receiver_len,
        envelope, len, &content_type, opened, KC_GROUP_PLAINTEXT_MAX,
        &opened_len, fixture.receiver, sizeof(fixture.receiver),
        &fixture.receiver_len) == KC_OK, "maximum payload decrypts");
    group_expect(opened_len == KC_GROUP_PLAINTEXT_MAX &&
        memcmp(plaintext, opened, opened_len) == 0,
        "maximum payload matches");
    plaintext[0] = 255u;
    group_expect(kc_group_encrypt(fixture.sender, fixture.sender_len,
        KC_CONTENT_TEXT, plaintext, 1u, envelope,
        kc_group_encrypt_bound(KC_GROUP_PLAINTEXT_MAX), &len,
        fixture.sender, sizeof(fixture.sender), &fixture.sender_len) ==
        KC_ERR_MALFORMED, "invalid UTF-8 text rejected");
    group_expect(kc_group_encrypt(fixture.sender, fixture.sender_len,
        KC_CONTENT_FILE, plaintext, 1u, envelope,
        kc_group_encrypt_bound(KC_GROUP_PLAINTEXT_MAX), &len,
        fixture.sender, sizeof(fixture.sender), &fixture.sender_len) == KC_OK,
        "binary file content remains supported");
    kc_store_u32(fixture.sender + 154, UINT32_MAX);
    group_expect(kc_group_encrypt(fixture.sender, fixture.sender_len,
        KC_CONTENT_FILE, plaintext, 1u, envelope,
        kc_group_encrypt_bound(KC_GROUP_PLAINTEXT_MAX), &len,
        fixture.sender, sizeof(fixture.sender), &fixture.sender_len) ==
        KC_ERR_BAD_STATE, "sender counter exhaustion rejected");
    free(plaintext);
    free(envelope);
    free(opened);
}

int kc_run_group_tests(void)
{
    kc_group_test_failures = 0;
    test_group_roundtrip();
    test_group_out_of_order();
    test_group_authentication();
    test_group_membership_rotation();
    test_group_cross_epoch_replay();
    test_group_distribution_validation();
    test_group_bounded_skip();
    test_group_capacity_and_malformed();
    test_group_members_build();
    test_group_payload_limits();
    return kc_group_test_failures;
}
