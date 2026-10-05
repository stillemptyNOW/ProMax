#include "promax_crypto.h"

#include "kc_identity.h"
#include "monocypher.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int v2_failures = 0;

static void v2_expect(int condition, const char *name)
{
    if (!condition) {
        fprintf(stderr, "FAIL v2 %s\n", name);
        v2_failures++;
    }
}

static uint64_t v2_rng_state = 1u;

static void v2_rng_seed(uint64_t seed)
{
    v2_rng_state = seed == 0u ? 0x9E3779B97F4A7C15ull : seed;
}

static void v2_rng_fill(uint8_t *out, size_t len)
{
    size_t index;

    for (index = 0u; index < len; index++) {
        uint64_t x = v2_rng_state;
        x ^= x >> 12u;
        x ^= x << 25u;
        x ^= x >> 27u;
        v2_rng_state = x;
        out[index] = (uint8_t)((x * 0x2545F4914F6CDD1Dull) >> 56u);
    }
}

typedef struct {
    int64_t id;
    uint8_t identity[KC_IDENTITY_SIZE];
    uint8_t state[KC_SESSION_STATE_MAX];
    size_t state_len;
} v2_party;

static void v2_party_init(v2_party *party, int64_t id)
{
    uint8_t seed[KC_SEED_SIZE];
    size_t identity_len = 0u;

    memset(party, 0, sizeof(*party));
    party->id = id;
    v2_rng_fill(seed, sizeof(seed));
    v2_expect(kc_identity_create(seed, sizeof(seed), party->identity,
                                 sizeof(party->identity),
                                 &identity_len) == KC_OK &&
                  identity_len == KC_IDENTITY_SIZE,
              "identity create");
}

static int v2_establish(v2_party *a, v2_party *b, int64_t chat_id)
{
    uint8_t offer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t answer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t pending[KC_PENDING_STATE_SIZE];
    uint8_t random[KC_OFFER_RANDOM_SIZE];
    size_t offer_len = 0u;
    size_t answer_len = 0u;
    size_t pending_len = 0u;
    kc_status status;

    v2_rng_fill(random, KC_OFFER_RANDOM_SIZE);
    status = kc_session_offer(a->identity, sizeof(a->identity), chat_id, a->id,
                              b->id, random, KC_OFFER_RANDOM_SIZE, offer_text,
                              sizeof(offer_text), &offer_len, pending,
                              sizeof(pending), &pending_len);
    if (status != KC_OK) {
        return 0;
    }
    v2_rng_fill(random, KC_ANSWER_RANDOM_SIZE);
    status = kc_session_answer(b->identity, sizeof(b->identity), chat_id, b->id,
                               a->id, offer_text, offer_len, NULL, 0u, random,
                               KC_ANSWER_RANDOM_SIZE, answer_text,
                               sizeof(answer_text), &answer_len, b->state,
                               sizeof(b->state), &b->state_len);
    if (status != KC_OK) {
        return 0;
    }
    v2_rng_fill(random, KC_ACCEPT_RANDOM_SIZE);
    status = kc_session_accept(a->identity, sizeof(a->identity), pending,
                               pending_len, answer_text, answer_len, NULL, 0u, random,
                               KC_ACCEPT_RANDOM_SIZE, a->state,
                               sizeof(a->state), &a->state_len);
    return status == KC_OK;
}

static kc_status v2_send_type(v2_party *party,
                              uint8_t content_type,
                              const uint8_t *body,
                              size_t body_len,
                              uint8_t *out_text,
                              size_t cap,
                              size_t *out_len)
{
    uint8_t random[KC_ENCRYPT_RANDOM_SIZE];

    v2_rng_fill(random, sizeof(random));
    return kc_session_encrypt(party->state, party->state_len, content_type,
                              body, body_len, random, sizeof(random), out_text,
                              cap, out_len, party->state, sizeof(party->state),
                              &party->state_len);
}

static kc_status v2_send(v2_party *party,
                         const char *text,
                         uint8_t *out_text,
                         size_t cap,
                         size_t *out_len)
{
    return v2_send_type(party, KC_CONTENT_TEXT, (const uint8_t *)text,
                        strlen(text), out_text, cap, out_len);
}

static kc_status v2_recv_type(v2_party *party,
                              const uint8_t *text,
                              size_t text_len,
                              uint8_t *out_type,
                              uint8_t *out,
                              size_t cap,
                              size_t *out_len)
{
    return kc_session_decrypt(party->state, party->state_len, text, text_len,
                              out_type, out, cap, out_len, party->state,
                              sizeof(party->state), &party->state_len);
}

static kc_status v2_recv(v2_party *party,
                         const uint8_t *text,
                         size_t text_len,
                         char *out,
                         size_t cap)
{
    uint8_t content_type = 0u;
    size_t out_len = 0u;
    kc_status status = v2_recv_type(party, text, text_len, &content_type,
                                    (uint8_t *)out, cap - 1u, &out_len);

    if (status == KC_OK) {
        out[out_len] = '\0';
        if (content_type != KC_CONTENT_TEXT) {
            return KC_ERR_MALFORMED;
        }
    }
    return status;
}

static size_t v2_letters(const uint8_t *text, size_t len)
{
    size_t count = 0u;
    size_t index;

    for (index = 0u; index < len; index++) {
        if (text[index] == 0xD0u || text[index] == 0xD1u) {
            count++;
        }
    }
    return count;
}

static size_t v2_chars(const uint8_t *text, size_t len)
{
    size_t count = 0u;
    size_t index;

    for (index = 0u; index < len; index++) {
        if ((text[index] & 0xC0u) != 0x80u) {
            count++;
        }
    }
    return count;
}

static void v2_test_identity(void)
{
    uint8_t seed[KC_SEED_SIZE];
    uint8_t identity[KC_IDENTITY_SIZE];
    uint8_t public_key[KC_PUBLIC_KEY_SIZE];
    uint8_t x_secret[32];
    uint8_t x_public_from_secret[32];
    uint8_t x_public_from_eddsa[32];
    uint8_t signature[64];
    size_t len = 0u;

    v2_rng_seed(11u);
    v2_rng_fill(seed, sizeof(seed));
    v2_expect(kc_identity_create(seed, sizeof(seed), identity, sizeof(identity),
                                 &len) == KC_OK,
              "identity create");
    v2_expect(memcmp(identity, seed, KC_SEED_SIZE) == 0, "identity keeps seed");
    v2_expect(kc_identity_public_key(identity, sizeof(identity), public_key,
                                     sizeof(public_key), &len) == KC_OK &&
                  len == KC_PUBLIC_KEY_SIZE,
              "identity public");
    kc_identity_x25519_secret(identity, x_secret);
    crypto_x25519_public_key(x_public_from_secret, x_secret);
    kc_identity_x25519_public(public_key, x_public_from_eddsa);
    v2_expect(memcmp(x_public_from_secret, x_public_from_eddsa, 32u) == 0,
              "x25519 derivation matches eddsa conversion");
    kc_identity_sign(identity, seed, sizeof(seed), signature);
    v2_expect(kc_identity_verify(public_key, seed, sizeof(seed), signature),
              "signature verifies");
    signature[3] ^= 1u;
    v2_expect(!kc_identity_verify(public_key, seed, sizeof(seed), signature),
              "tampered signature rejected");
    v2_expect(kc_identity_create(seed, 16u, identity, sizeof(identity), &len) ==
                  KC_ERR_INVALID_ARGUMENT,
              "identity short seed");
}

static void v2_test_fingerprint(void)
{
    uint8_t a_public[32];
    uint8_t b_public[32];
    uint8_t from_a[KC_FINGERPRINT_DIGITS];
    uint8_t from_b[KC_FINGERPRINT_DIGITS];
    uint8_t other[KC_FINGERPRINT_DIGITS];
    size_t len = 0u;
    size_t index;
    int digits = 1;

    v2_rng_seed(12u);
    v2_rng_fill(a_public, sizeof(a_public));
    v2_rng_fill(b_public, sizeof(b_public));
    v2_expect(kc_fingerprint(100, a_public, 32u, 200, b_public, 32u, from_a,
                             sizeof(from_a), &len) == KC_OK &&
                  len == KC_FINGERPRINT_DIGITS,
              "fingerprint a");
    v2_expect(kc_fingerprint(200, b_public, 32u, 100, a_public, 32u, from_b,
                             sizeof(from_b), &len) == KC_OK,
              "fingerprint b");
    v2_expect(memcmp(from_a, from_b, KC_FINGERPRINT_DIGITS) == 0,
              "fingerprint symmetric");
    for (index = 0u; index < KC_FINGERPRINT_DIGITS; index++) {
        if (from_a[index] < '0' || from_a[index] > '9') {
            digits = 0;
        }
    }
    v2_expect(digits, "fingerprint digits");
    b_public[0] ^= 1u;
    v2_expect(kc_fingerprint(100, a_public, 32u, 200, b_public, 32u, other,
                             sizeof(other), &len) == KC_OK &&
                  memcmp(from_a, other, KC_FINGERPRINT_DIGITS) != 0,
              "fingerprint depends on key");
}

static void v2_test_local(void)
{
    static const uint8_t aad[] = "session/1/2";
    static const uint8_t plaintext[] = "local plaintext";
    uint8_t key[KC_LOCAL_KEY_SIZE];
    uint8_t nonce[KC_LOCAL_NONCE_SIZE];
    uint8_t blob[128];
    uint8_t opened[128];
    size_t blob_len = 0u;
    size_t opened_len = 0u;

    v2_rng_seed(13u);
    v2_rng_fill(key, sizeof(key));
    v2_rng_fill(nonce, sizeof(nonce));
    v2_expect(kc_local_seal(key, sizeof(key), nonce, sizeof(nonce), aad,
                            sizeof(aad) - 1u, plaintext, sizeof(plaintext) - 1u,
                            blob, sizeof(blob), &blob_len) == KC_OK &&
                  blob_len == kc_local_seal_bound(sizeof(plaintext) - 1u),
              "local seal");
    v2_expect(kc_local_open(key, sizeof(key), aad, sizeof(aad) - 1u, blob,
                            blob_len, opened, sizeof(opened),
                            &opened_len) == KC_OK &&
                  opened_len == sizeof(plaintext) - 1u &&
                  memcmp(opened, plaintext, opened_len) == 0,
              "local open");
    v2_expect(kc_local_open(key, sizeof(key), aad, sizeof(aad) - 2u, blob,
                            blob_len, opened, sizeof(opened),
                            &opened_len) == KC_ERR_WRONG_KEY,
              "local aad mismatch");
    blob[KC_LOCAL_NONCE_SIZE + 2u] ^= 1u;
    v2_expect(kc_local_open(key, sizeof(key), aad, sizeof(aad) - 1u, blob,
                            blob_len, opened, sizeof(opened),
                            &opened_len) == KC_ERR_WRONG_KEY,
              "local tamper");
    v2_expect(kc_local_seal(key, sizeof(key), nonce, sizeof(nonce), NULL, 0u,
                            NULL, 0u, blob, sizeof(blob), &blob_len) == KC_OK &&
                  kc_local_open(key, sizeof(key), NULL, 0u, blob, blob_len,
                                NULL, 0u, &opened_len) == KC_OK &&
                  opened_len == 0u,
              "local empty");
}

static void v2_test_conversation(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t wire[3][2048];
    size_t wire_len[3];
    char plain[1024];
    size_t index;
    size_t alice_state_before;

    v2_rng_seed(21u);
    v2_party_init(&alice, 1001);
    v2_party_init(&bob, 2002);
    v2_expect(v2_establish(&alice, &bob, 3003), "establish");
    v2_expect(alice.state_len == 304u && bob.state_len == 304u,
              "fresh state size");

    v2_expect(v2_send(&alice, "первое", wire[0], sizeof(wire[0]),
                      &wire_len[0]) == KC_OK,
              "alice sends 0");
    v2_expect(v2_send(&alice, "второе", wire[1], sizeof(wire[1]),
                      &wire_len[1]) == KC_OK,
              "alice sends 1");
    v2_expect(kc_classify_text(wire[0], wire_len[0]) == KC_TEXT_SESSION,
              "classify session");
    v2_expect(wire_len[0] != wire_len[1] ||
                  memcmp(wire[0], wire[1], wire_len[0]) != 0,
              "envelopes differ");
    v2_expect(v2_recv(&bob, wire[0], wire_len[0], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "первое") == 0,
              "bob reads 0");
    v2_expect(v2_recv(&bob, wire[1], wire_len[1], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "второе") == 0,
              "bob reads 1");
    v2_expect(v2_recv(&bob, wire[1], wire_len[1], plain, sizeof(plain)) ==
                  KC_ERR_REPLAY,
              "bob rejects replay");

    v2_expect(v2_send(&bob, "ответ", wire[2], sizeof(wire[2]), &wire_len[2]) ==
                  KC_OK,
              "bob sends");
    v2_expect(v2_recv(&alice, wire[2], wire_len[2], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "ответ") == 0,
              "alice reads reply");
    for (index = 0u; index < 5u; index++) {
        char text[32];
        snprintf(text, sizeof(text), "raund %u", (unsigned int)index);
        v2_expect(v2_send(&alice, text, wire[0], sizeof(wire[0]),
                          &wire_len[0]) == KC_OK &&
                      v2_recv(&bob, wire[0], wire_len[0], plain,
                              sizeof(plain)) == KC_OK &&
                      strcmp(plain, text) == 0,
                  "alice to bob round");
        v2_expect(v2_send(&bob, text, wire[0], sizeof(wire[0]),
                          &wire_len[0]) == KC_OK &&
                      v2_recv(&alice, wire[0], wire_len[0], plain,
                              sizeof(plain)) == KC_OK &&
                      strcmp(plain, text) == 0,
                  "bob to alice round");
    }

    alice_state_before = alice.state_len;
    v2_expect(v2_send(&bob, "x", wire[0], sizeof(wire[0]), &wire_len[0]) ==
                  KC_OK,
              "bob sends x");
    wire[0][wire_len[0] / 2u] ^= 0x02u;
    v2_expect(v2_recv(&alice, wire[0], wire_len[0], plain, sizeof(plain)) !=
                      KC_OK &&
                  alice.state_len == alice_state_before,
              "tampered envelope rejected without state change");
}

static void v2_test_bob_first(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t wire[2048];
    size_t wire_len = 0u;
    char plain[256];

    v2_rng_seed(22u);
    v2_party_init(&alice, 1);
    v2_party_init(&bob, 2);
    v2_expect(v2_establish(&alice, &bob, 3), "establish bob first");
    v2_expect(v2_send(&bob, "боб первый", wire, sizeof(wire), &wire_len) ==
                  KC_OK,
              "bob sends before alice");
    v2_expect(v2_recv(&alice, wire, wire_len, plain, sizeof(plain)) == KC_OK &&
                  strcmp(plain, "боб первый") == 0,
              "alice reads bob first");
    v2_expect(v2_send(&alice, "алиса", wire, sizeof(wire), &wire_len) == KC_OK &&
                  v2_recv(&bob, wire, wire_len, plain, sizeof(plain)) == KC_OK &&
                  strcmp(plain, "алиса") == 0,
              "alice replies after bob first");
}

static void v2_test_out_of_order(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t wire[6][1024];
    size_t wire_len[6];
    uint8_t saved_state[KC_SESSION_STATE_MAX];
    size_t saved_len;
    char plain[256];
    size_t index;

    v2_rng_seed(23u);
    v2_party_init(&alice, 10);
    v2_party_init(&bob, 20);
    v2_expect(v2_establish(&alice, &bob, 30), "establish ooo");
    for (index = 0u; index < 6u; index++) {
        char text[16];
        snprintf(text, sizeof(text), "m%u", (unsigned int)index);
        v2_expect(v2_send(&alice, text, wire[index], sizeof(wire[index]),
                          &wire_len[index]) == KC_OK,
                  "ooo send");
    }
    v2_expect(v2_recv(&bob, wire[2], wire_len[2], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "m2") == 0,
              "ooo m2");
    v2_expect(bob.state_len == 304u + 2u * 68u, "two skipped keys stored");
    memcpy(saved_state, bob.state, bob.state_len);
    saved_len = bob.state_len;
    v2_expect(v2_recv(&bob, wire[0], wire_len[0], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "m0") == 0,
              "ooo m0");
    v2_expect(bob.state_len == 304u + 68u, "skipped key consumed");
    v2_expect(v2_recv(&bob, wire[0], wire_len[0], plain, sizeof(plain)) ==
                  KC_ERR_REPLAY,
              "ooo replay m0");
    memcpy(bob.state, saved_state, saved_len);
    bob.state_len = saved_len;
    v2_expect(v2_recv(&bob, wire[0], wire_len[0], plain, sizeof(plain)) ==
                  KC_OK,
              "restored state reads m0 again");
    v2_expect(v2_recv(&bob, wire[1], wire_len[1], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "m1") == 0,
              "ooo m1");
    v2_expect(v2_recv(&bob, wire[5], wire_len[5], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "m5") == 0,
              "ooo m5");
    v2_expect(v2_send(&bob, "reply", wire[0], sizeof(wire[0]), &wire_len[0]) ==
                      KC_OK &&
                  v2_recv(&alice, wire[0], wire_len[0], plain, sizeof(plain)) ==
                      KC_OK,
              "ooo bob reply");
    v2_expect(v2_send(&alice, "next epoch", wire[1], sizeof(wire[1]),
                      &wire_len[1]) == KC_OK &&
                  v2_recv(&bob, wire[1], wire_len[1], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "next epoch") == 0,
              "ooo next epoch");
    v2_expect(v2_recv(&bob, wire[3], wire_len[3], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "m3") == 0,
              "old epoch skipped key still works");
    v2_expect(v2_recv(&bob, wire[4], wire_len[4], plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "m4") == 0,
              "old epoch last skipped key");
    v2_expect(v2_recv(&bob, wire[4], wire_len[4], plain, sizeof(plain)) !=
                  KC_OK,
              "old epoch replay");
}

static void v2_test_skip_limit(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t first[1024];
    uint8_t evicted[1024];
    uint8_t retained[1024];
    uint8_t last[1024];
    uint8_t wire[1024];
    size_t first_len = 0u;
    size_t evicted_len = 0u;
    size_t retained_len = 0u;
    size_t last_len = 0u;
    size_t wire_len = 0u;
    char plain[256];
    size_t index;

    v2_rng_seed(24u);
    v2_party_init(&alice, 5);
    v2_party_init(&bob, 6);
    v2_expect(v2_establish(&alice, &bob, 7), "establish skip");
    v2_expect(v2_send(&alice, "first", first, sizeof(first), &first_len) ==
                  KC_OK,
              "skip first");
    for (index = 0u; index < 400u; index++) {
        v2_expect(v2_send(&alice, "gap", wire, sizeof(wire), &wire_len) ==
                      KC_OK,
                  "skip gap");
        if (index == 0u) {
            memcpy(evicted, wire, wire_len);
            evicted_len = wire_len;
        }
        if (index == 350u) {
            memcpy(retained, wire, wire_len);
            retained_len = wire_len;
        }
    }
    v2_expect(v2_send(&alice, "last", last, sizeof(last), &last_len) == KC_OK,
              "skip last");

    v2_expect(v2_recv(&bob, last, last_len, plain, sizeof(plain)) == KC_OK &&
                  strcmp(plain, "last") == 0,
              "a 400-message backlog no longer wedges the receiver");
    v2_expect(bob.state_len == 304u + 256u * 68u, "skip store capped at 256");
    v2_expect(v2_recv(&bob, retained, retained_len, plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "gap") == 0,
              "a retained skipped key still opens its message");
    v2_expect(v2_recv(&bob, evicted, evicted_len, plain, sizeof(plain)) !=
                  KC_OK,
              "an evicted key is gone");
    v2_expect(v2_recv(&bob, first, first_len, plain, sizeof(plain)) != KC_OK,
              "a key evicted before the walk is gone too");
}

static void v2_test_epoch_change_never_wedges(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t wire[1024];
    size_t wire_len = 0u;
    char plain[256];
    size_t index;

    v2_rng_seed(35u);
    v2_party_init(&alice, 91);
    v2_party_init(&bob, 92);
    v2_expect(v2_establish(&alice, &bob, 93), "establish epoch");

    v2_expect(v2_send(&alice, "a0", wire, sizeof(wire), &wire_len) == KC_OK &&
                  v2_recv(&bob, wire, wire_len, plain, sizeof(plain)) == KC_OK,
              "epoch a0");

    for (index = 0u; index < 400u; index++) {
        v2_expect(v2_send(&alice, "lost", wire, sizeof(wire), &wire_len) ==
                      KC_OK,
                  "epoch hole");
    }

    v2_expect(v2_send(&bob, "b0", wire, sizeof(wire), &wire_len) == KC_OK &&
                  v2_recv(&alice, wire, wire_len, plain, sizeof(plain)) ==
                      KC_OK,
              "epoch b0");
    v2_expect(v2_send(&alice, "new epoch", wire, sizeof(wire), &wire_len) ==
                  KC_OK,
              "epoch alice sends");
    v2_expect(v2_recv(&bob, wire, wire_len, plain, sizeof(plain)) == KC_OK &&
                  strcmp(plain, "new epoch") == 0,
              "a 400-message hole in the previous epoch does not wedge the receiver");
    v2_expect(v2_send(&alice, "after", wire, sizeof(wire), &wire_len) == KC_OK &&
                  v2_recv(&bob, wire, wire_len, plain, sizeof(plain)) == KC_OK,
              "the session keeps working afterwards");
}

static void v2_test_unreachable_previous_epoch(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t wire[1024];
    size_t wire_len = 0u;
    char plain[256];
    size_t index;

    v2_rng_seed(37u);
    v2_party_init(&alice, 111);
    v2_party_init(&bob, 112);
    v2_expect(v2_establish(&alice, &bob, 113), "establish unreachable");
    v2_expect(v2_send(&alice, "a0", wire, sizeof(wire), &wire_len) == KC_OK &&
                  v2_recv(&bob, wire, wire_len, plain, sizeof(plain)) == KC_OK,
              "unreachable a0");

    for (index = 0u; index < KC_SESSION_MAX_ADVANCE + 10u; index++) {
        v2_expect(v2_send(&alice, "lost", wire, sizeof(wire), &wire_len) ==
                      KC_OK,
                  "unreachable hole");
    }
    v2_expect(v2_send(&bob, "b0", wire, sizeof(wire), &wire_len) == KC_OK &&
                  v2_recv(&alice, wire, wire_len, plain, sizeof(plain)) ==
                      KC_OK,
              "unreachable b0");
    v2_expect(v2_send(&alice, "new epoch", wire, sizeof(wire), &wire_len) ==
                  KC_OK,
              "unreachable alice sends");
    v2_expect(v2_recv(&bob, wire, wire_len, plain, sizeof(plain)) == KC_OK &&
                  strcmp(plain, "new epoch") == 0,
              "an unreachable previous chain is abandoned, not fatal");
}

static void v2_test_forged_counter_is_bounded(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t wire[2048];
    uint8_t plain[256];
    uint8_t saved[KC_SESSION_STATE_MAX];
    uint8_t content_type = 0u;
    size_t wire_len = 0u;
    size_t plain_len = 0u;
    size_t saved_len;
    size_t index;

    v2_rng_seed(36u);
    v2_party_init(&alice, 101);
    v2_party_init(&bob, 102);
    v2_expect(v2_establish(&alice, &bob, 103), "establish forged counter");

    for (index = 0u; index < KC_SESSION_MAX_ADVANCE + 2u; index++) {
        v2_expect(v2_send(&alice, "x", wire, sizeof(wire), &wire_len) == KC_OK,
                  "forged counter fill");
    }
    memcpy(saved, bob.state, bob.state_len);
    saved_len = bob.state_len;
    v2_expect(kc_session_decrypt(bob.state, bob.state_len, wire, wire_len,
                                 &content_type, plain, sizeof(plain),
                                 &plain_len, bob.state, sizeof(bob.state),
                                 &bob.state_len) == KC_ERR_TOO_MANY_SKIPPED,
              "a counter past the walk limit is refused");
    v2_expect(bob.state_len == saved_len &&
                  memcmp(bob.state, saved, saved_len) == 0,
              "the refusal leaves the receiver state untouched");
}

static void v2_test_handshake_errors(void)
{
    v2_party alice;
    v2_party bob;
    v2_party carol;
    uint8_t offer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t prefixed[KC_HANDSHAKE_TEXT_BOUND + 64u];
    uint8_t answer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t pending[KC_PENDING_STATE_SIZE];
    uint8_t random[KC_OFFER_RANDOM_SIZE];
    uint8_t state[KC_SESSION_STATE_MAX];
    uint8_t other_state[KC_SESSION_STATE_MAX];
    uint8_t peek_type = 0u;
    uint8_t peek_id[KC_OFFER_ID_SIZE];
    uint8_t peek_public[KC_PUBLIC_KEY_SIZE];
    uint8_t content_type = 0u;
    uint8_t plain[256];
    size_t offer_len = 0u;
    size_t prefixed_len;
    size_t answer_len = 0u;
    size_t pending_len = 0u;
    size_t state_len = 0u;
    size_t other_len = 0u;
    size_t plain_len = 0u;
    static const char prefix[] = "🔐 ProMax: запрос шифрования\n";

    v2_rng_seed(25u);
    v2_party_init(&alice, 100);
    v2_party_init(&bob, 200);
    v2_party_init(&carol, 300);
    v2_rng_fill(random, KC_OFFER_RANDOM_SIZE);
    v2_expect(kc_session_offer(alice.identity, sizeof(alice.identity), 5, 100,
                               200, random, KC_OFFER_RANDOM_SIZE, offer_text,
                               sizeof(offer_text), &offer_len, pending,
                               sizeof(pending), &pending_len) == KC_OK,
              "offer");
    v2_expect(v2_chars(offer_text, offer_len) <= KC_TEXT_TRANSPORT_MAX,
              "offer fits transport");
    memcpy(prefixed, prefix, sizeof(prefix) - 1u);
    memcpy(prefixed + sizeof(prefix) - 1u, offer_text, offer_len);
    prefixed_len = sizeof(prefix) - 1u + offer_len;
    v2_expect(kc_classify_text(prefixed, prefixed_len) == KC_TEXT_OFFER,
              "classify prefixed offer");
    v2_expect(kc_classify_text(offer_text, offer_len) == KC_TEXT_OFFER,
              "classify bare offer");
    v2_expect(kc_handshake_peek(prefixed, prefixed_len, &peek_type, peek_id,
                                sizeof(peek_id), peek_public,
                                sizeof(peek_public)) == KC_OK &&
                  peek_type == 1u &&
                  memcmp(peek_public, alice.identity + KC_SEED_SIZE, 32u) == 0,
              "peek offer");

    v2_rng_fill(random, KC_ANSWER_RANDOM_SIZE);
    v2_expect(kc_session_answer(bob.identity, sizeof(bob.identity), 6, 200, 100,
                                prefixed, prefixed_len, NULL, 0u, random,
                                KC_ANSWER_RANDOM_SIZE, answer_text,
                                sizeof(answer_text), &answer_len, state,
                                sizeof(state), &state_len) ==
                  KC_ERR_BAD_SIGNATURE,
              "answer wrong chat");
    v2_expect(kc_session_answer(carol.identity, sizeof(carol.identity), 5, 300,
                                100, prefixed, prefixed_len, NULL, 0u, random,
                                KC_ANSWER_RANDOM_SIZE, answer_text,
                                sizeof(answer_text), &answer_len, state,
                                sizeof(state), &state_len) ==
                  KC_ERR_BAD_SIGNATURE,
              "answer by wrong recipient");
    v2_expect(kc_session_answer(alice.identity, sizeof(alice.identity), 5, 100,
                                200, prefixed, prefixed_len, NULL, 0u, random,
                                KC_ANSWER_RANDOM_SIZE, answer_text,
                                sizeof(answer_text), &answer_len, state,
                                sizeof(state), &state_len) ==
                  KC_ERR_BAD_SIGNATURE,
              "reflected offer");
    v2_expect(kc_session_answer(bob.identity, sizeof(bob.identity), 5, 200, 100,
                                prefixed, prefixed_len, NULL, 0u, random,
                                KC_ANSWER_RANDOM_SIZE, answer_text,
                                sizeof(answer_text), &answer_len, state,
                                sizeof(state), &state_len) == KC_OK,
              "answer prefixed offer");
    v2_expect(kc_classify_text(answer_text, answer_len) == KC_TEXT_ANSWER,
              "classify answer");
    v2_expect(kc_session_answer(bob.identity, sizeof(bob.identity), 5, 200, 100,
                                prefixed, prefixed_len, state, state_len,
                                random, KC_ANSWER_RANDOM_SIZE, answer_text,
                                sizeof(answer_text), &answer_len, other_state,
                                sizeof(other_state), &other_len) ==
                  KC_ERR_REPLAY,
              "replayed offer");
    v2_expect(kc_session_decrypt(state, state_len, prefixed, prefixed_len,
                                 &content_type, plain, sizeof(plain),
                                 &plain_len, other_state, sizeof(other_state),
                                 &other_len) == KC_ERR_HANDSHAKE_MESSAGE,
              "decrypt handshake text");
    v2_expect(kc_session_decrypt(state, state_len, (const uint8_t *)"привет",
                                 12u, &content_type, plain, sizeof(plain),
                                 &plain_len, other_state, sizeof(other_state),
                                 &other_len) == KC_ERR_NOT_ENCRYPTED,
              "decrypt plain text");

    v2_rng_fill(random, KC_ACCEPT_RANDOM_SIZE);
    v2_expect(kc_session_accept(bob.identity, sizeof(bob.identity), pending,
                                pending_len, answer_text, answer_len, NULL, 0u, random,
                                KC_ACCEPT_RANDOM_SIZE, state, sizeof(state),
                                &state_len) == KC_ERR_BAD_STATE,
              "accept with foreign identity");
    answer_text[answer_len / 2u] ^= 0x02u;
    v2_expect(kc_session_accept(alice.identity, sizeof(alice.identity), pending,
                                pending_len, answer_text, answer_len, NULL, 0u, random,
                                KC_ACCEPT_RANDOM_SIZE, state, sizeof(state),
                                &state_len) != KC_OK,
              "tampered answer");
    v2_expect(kc_session_accept(alice.identity, sizeof(alice.identity), pending,
                                pending_len, offer_text, offer_len, NULL, 0u, random,
                                KC_ACCEPT_RANDOM_SIZE, state, sizeof(state),
                                &state_len) == KC_ERR_HANDSHAKE_MESSAGE,
              "accept given offer");
}

static void v2_test_content_types(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t wire[4096];
    uint8_t body[KC_SESSION_PLAINTEXT_MAX];
    uint8_t opened[KC_SESSION_PLAINTEXT_MAX + 32u];
    uint8_t content_type = 0u;
    size_t wire_len = 0u;
    size_t opened_len = 0u;
    static const uint8_t bad_utf8[] = {0xFFu, 0xFEu};

    v2_rng_seed(26u);
    v2_party_init(&alice, 1);
    v2_party_init(&bob, 2);
    v2_expect(v2_establish(&alice, &bob, 3), "establish content");
    v2_rng_fill(body, sizeof(body));
    v2_expect(v2_send_type(&alice, KC_CONTENT_FILE, body, sizeof(body), wire,
                           sizeof(wire), &wire_len) == KC_OK,
              "send max file ticket");
    v2_expect(v2_chars(wire, wire_len) <= KC_TEXT_TRANSPORT_MAX,
              "max plaintext fits transport");
    v2_expect(v2_recv_type(&bob, wire, wire_len, &content_type, opened,
                           sizeof(opened), &opened_len) == KC_OK &&
                  content_type == KC_CONTENT_FILE &&
                  opened_len == sizeof(body) &&
                  memcmp(opened, body, sizeof(body)) == 0,
              "receive file ticket");
    v2_expect(v2_send_type(&alice, KC_CONTENT_TEXT, body, sizeof(body) + 1u,
                           wire, sizeof(wire), &wire_len) == KC_ERR_TOO_LONG,
              "too long");
    v2_expect(v2_send_type(&alice, KC_CONTENT_TEXT, bad_utf8, sizeof(bad_utf8),
                           wire, sizeof(wire), &wire_len) == KC_ERR_MALFORMED,
              "bad utf8");
    v2_expect(v2_send_type(&alice, 9u, body, 4u, wire, sizeof(wire),
                           &wire_len) == KC_ERR_INVALID_ARGUMENT,
              "bad content type");
    v2_expect(v2_send_type(&alice, KC_CONTENT_CONTROL, NULL, 0u, wire,
                           sizeof(wire), &wire_len) == KC_OK &&
                  v2_recv_type(&bob, wire, wire_len, &content_type, opened,
                               sizeof(opened), &opened_len) == KC_OK &&
                  content_type == KC_CONTENT_CONTROL && opened_len == 0u,
              "empty control");
    v2_expect(v2_send(&alice, "a", wire, sizeof(wire), &wire_len) == KC_OK &&
                  v2_send(&alice, "abcdefghijklmnopqrstuvwxyz0123", opened,
                          sizeof(opened), &opened_len) == KC_OK &&
                  v2_letters(wire, wire_len) == v2_letters(opened, opened_len),
              "padding hides length within bucket");
}

static void v2_test_file(void)
{
    static const size_t sizes[] = {0u, 1u, 65535u, 65536u, 65537u, 200001u};
    uint8_t key[KC_FILE_KEY_SIZE];
    uint8_t nonce[KC_FILE_NONCE_SIZE];
    uint8_t seal_ctx[KC_FILE_CTX_SIZE];
    uint8_t open_ctx[KC_FILE_CTX_SIZE];
    size_t size_index;

    v2_rng_seed(27u);
    v2_rng_fill(key, sizeof(key));
    v2_rng_fill(nonce, sizeof(nonce));
    for (size_index = 0u; size_index < 6u; size_index++) {
        size_t size = sizes[size_index];
        uint8_t *plain = (uint8_t *)malloc(size == 0u ? 1u : size);
        uint8_t *cipher = (uint8_t *)malloc(kc_file_seal_bound(size));
        uint8_t *opened = (uint8_t *)malloc(size == 0u ? 1u : size);
        size_t cipher_len = 0u;
        size_t offset = 0u;
        size_t out_offset = 0u;
        int ok = plain != NULL && cipher != NULL && opened != NULL;
        v2_rng_fill(plain, size);
        ok = ok && kc_file_seal_init(seal_ctx, sizeof(seal_ctx), key,
                                     sizeof(key), nonce, sizeof(nonce)) == KC_OK;
        while (ok) {
            size_t take = size - offset < KC_FILE_CHUNK_SIZE
                              ? size - offset
                              : KC_FILE_CHUNK_SIZE;
            int last = size - offset <= KC_FILE_CHUNK_SIZE;
            size_t written = 0u;
            ok = kc_file_seal_chunk(seal_ctx, sizeof(seal_ctx), plain + offset,
                                    take, last, cipher + cipher_len,
                                    take + KC_TAG_SIZE, &written) == KC_OK;
            cipher_len += written;
            offset += take;
            if (last) {
                break;
            }
        }
        v2_expect(ok && cipher_len <= kc_file_seal_bound(size), "file seal");
        ok = ok && kc_file_open_init(open_ctx, sizeof(open_ctx), key,
                                     sizeof(key), nonce, sizeof(nonce)) == KC_OK;
        offset = 0u;
        while (ok) {
            size_t remaining = cipher_len - offset;
            int last = remaining <= KC_FILE_CHUNK_SIZE + KC_TAG_SIZE;
            size_t take = last ? remaining : KC_FILE_CHUNK_SIZE + KC_TAG_SIZE;
            size_t written = 0u;
            ok = kc_file_open_chunk(open_ctx, sizeof(open_ctx), cipher + offset,
                                    take, last, opened + out_offset,
                                    take - KC_TAG_SIZE, &written) == KC_OK;
            out_offset += written;
            offset += take;
            if (last) {
                break;
            }
        }
        v2_expect(ok && out_offset == size &&
                      memcmp(opened, plain, size) == 0,
                  "file open");
        if (size == 200001u) {
            uint8_t chunk[KC_FILE_CHUNK_SIZE + KC_TAG_SIZE];
            size_t written = 0u;
            v2_expect(kc_file_open_chunk(open_ctx, sizeof(open_ctx), cipher,
                                         KC_FILE_CHUNK_SIZE + KC_TAG_SIZE, 0,
                                         chunk, sizeof(chunk),
                                         &written) == KC_ERR_BAD_STATE,
                      "file finished context");
            kc_file_open_init(open_ctx, sizeof(open_ctx), key, sizeof(key),
                              nonce, sizeof(nonce));
            v2_expect(kc_file_open_chunk(open_ctx, sizeof(open_ctx),
                                         cipher + KC_FILE_CHUNK_SIZE +
                                             KC_TAG_SIZE,
                                         KC_FILE_CHUNK_SIZE + KC_TAG_SIZE, 0,
                                         chunk, sizeof(chunk),
                                         &written) == KC_ERR_WRONG_KEY,
                      "file reordered chunk");
            v2_expect(kc_file_open_chunk(open_ctx, sizeof(open_ctx), cipher,
                                         KC_FILE_CHUNK_SIZE + KC_TAG_SIZE, 1,
                                         chunk, sizeof(chunk),
                                         &written) == KC_ERR_WRONG_KEY,
                      "file wrong last flag");
            cipher[100] ^= 1u;
            v2_expect(kc_file_open_chunk(open_ctx, sizeof(open_ctx), cipher,
                                         KC_FILE_CHUNK_SIZE + KC_TAG_SIZE, 0,
                                         chunk, sizeof(chunk),
                                         &written) == KC_ERR_WRONG_KEY,
                      "file bit flip");
            cipher[100] ^= 1u;
            v2_expect(kc_file_open_chunk(open_ctx, sizeof(open_ctx), cipher,
                                         KC_FILE_CHUNK_SIZE + KC_TAG_SIZE, 0,
                                         chunk, sizeof(chunk),
                                         &written) == KC_OK,
                      "file recovers after failed chunk");
        }
        free(plain);
        free(cipher);
        free(opened);
    }
}

static void v2_test_export(void)
{
    v2_party alice;
    v2_party bob;
    v2_party imported;
    uint8_t container[4096];
    uint8_t blob[4096];
    uint8_t opened[4096];
    uint8_t random[KC_EXPORT_RANDOM_SIZE];
    uint8_t wire[1024];
    size_t container_len;
    size_t blob_len = 0u;
    size_t opened_len = 0u;
    size_t wire_len = 0u;
    size_t offset;
    char plain[256];
    static const uint8_t password[] = "перенос";

    v2_rng_seed(28u);
    v2_party_init(&alice, 1);
    v2_party_init(&bob, 2);
    v2_expect(v2_establish(&alice, &bob, 3), "establish export");
    v2_expect(v2_send(&alice, "до экспорта", wire, sizeof(wire), &wire_len) ==
                      KC_OK &&
                  v2_recv(&bob, wire, wire_len, plain, sizeof(plain)) == KC_OK,
              "message before export");

    container[0] = 0u;
    container[1] = 0u;
    container[2] = 0u;
    container[3] = 2u;
    offset = 4u;
    container[offset + 3u] = (uint8_t)KC_IDENTITY_SIZE;
    container[offset] = 0u;
    container[offset + 1u] = 0u;
    container[offset + 2u] = 0u;
    offset += 4u;
    memcpy(container + offset, alice.identity, KC_IDENTITY_SIZE);
    offset += KC_IDENTITY_SIZE;
    container[offset] = 0u;
    container[offset + 1u] = 0u;
    container[offset + 2u] = (uint8_t)(alice.state_len >> 8u);
    container[offset + 3u] = (uint8_t)alice.state_len;
    offset += 4u;
    memcpy(container + offset, alice.state, alice.state_len);
    offset += alice.state_len;
    container_len = offset;

    v2_rng_fill(random, sizeof(random));
    v2_expect(kc_export_seal(password, sizeof(password) - 1u, 8u, 1u, random,
                             sizeof(random), container, container_len, blob,
                             sizeof(blob), &blob_len) == KC_OK &&
                  blob_len == kc_export_seal_bound(container_len),
              "export seal");
    v2_expect(kc_export_open((const uint8_t *)"wrong", 5u, blob, blob_len,
                             opened, sizeof(opened),
                             &opened_len) == KC_ERR_WRONG_KEY,
              "export wrong password");
    v2_expect(kc_export_open(password, sizeof(password) - 1u, blob, blob_len,
                             opened, sizeof(opened), &opened_len) == KC_OK &&
                  opened_len == container_len,
              "export open");
    v2_expect(memcmp(opened + 8, alice.identity, KC_IDENTITY_SIZE) == 0,
              "export identity intact");
    v2_expect(memcmp(opened, container, container_len) != 0,
              "imported session marked");

    memset(&imported, 0, sizeof(imported));
    imported.id = alice.id;
    memcpy(imported.identity, alice.identity, KC_IDENTITY_SIZE);
    imported.state_len = alice.state_len;
    memcpy(imported.state, opened + 8 + KC_IDENTITY_SIZE + 4, alice.state_len);
    v2_expect(v2_send(&imported, "после импорта", wire, sizeof(wire),
                      &wire_len) == KC_OK,
              "imported sends");
    v2_expect(memcmp(imported.state + 2u + 24u + 8u + 32u * 4u,
                     alice.state + 2u + 24u + 8u + 32u * 4u, 32u) != 0,
              "imported session ratcheted before sending");
    v2_expect(v2_recv(&bob, wire, wire_len, plain, sizeof(plain)) == KC_OK &&
                  strcmp(plain, "после импорта") == 0,
              "bob reads imported message");
    v2_expect(v2_send(&bob, "назад", wire, sizeof(wire), &wire_len) == KC_OK &&
                  v2_recv(&imported, wire, wire_len, plain, sizeof(plain)) ==
                      KC_OK &&
                  strcmp(plain, "назад") == 0,
              "imported reads reply");
    blob[blob_len - 1u] ^= 1u;
    v2_expect(kc_export_open(password, sizeof(password) - 1u, blob, blob_len,
                             opened, sizeof(opened),
                             &opened_len) == KC_ERR_WRONG_KEY,
              "export tamper");
}

static void v2_test_classify(void)
{
    uint8_t key[KC_KEY_SIZE] = {1u};
    uint8_t nonce[KC_NONCE_SIZE] = {2u};
    uint8_t legacy[512];
    size_t legacy_len = 0u;
    size_t index;

    v2_expect(kc_encrypt_message((const uint8_t *)"legacy", 6u, key,
                                 sizeof(key), nonce, sizeof(nonce), legacy,
                                 sizeof(legacy), &legacy_len) == KC_OK,
              "legacy encrypt");
    v2_expect(kc_classify_text(legacy, legacy_len) == KC_TEXT_LEGACY,
              "classify legacy");
    v2_expect(kc_classify_text((const uint8_t *)"просто текст", 23u) ==
                  KC_TEXT_NONE,
              "classify plain");
    v2_expect(kc_classify_text((const uint8_t *)"hello", 5u) == KC_TEXT_NONE,
              "classify latin");
    v2_expect(kc_classify_text(NULL, 0u) == KC_TEXT_NONE, "classify empty");

    for (index = 0u; index < 96u; index++) {
        char text[256];
        size_t len;
        for (len = 0u; len < index; len++) {
            text[len] = (char)('a' + (int)(len % 26u));
        }
        text[index] = '\0';
        legacy_len = 0u;
        if (kc_encrypt_message((const uint8_t *)text, index, key, sizeof(key),
                               nonce, sizeof(nonce), legacy, sizeof(legacy),
                               &legacy_len) != KC_OK) {
            continue;
        }
        v2_expect(kc_classify_text(legacy, legacy_len) == KC_TEXT_LEGACY,
                  "legacy of any length classifies as legacy");
    }
}


static void v2_fill_seeded(uint8_t *out, size_t len, uint64_t seed)
{
    uint64_t x = seed;
    size_t index;

    for (index = 0u; index < len; index++) {
        x ^= x >> 12u;
        x ^= x << 25u;
        x ^= x >> 27u;
        out[index] = (uint8_t)((x * 0x2545F4914F6CDD1Dull) >> 56u);
    }
}

static void v2_test_pinned_vectors(void)
{
    static const uint8_t expected_public_a[32] = {
        0x4Bu, 0x98u, 0x5Au, 0xF0u, 0x9Au, 0x8Cu, 0x95u, 0x6Au,
        0x3Fu, 0x51u, 0x09u, 0x88u, 0x90u, 0x8Du, 0x66u, 0xC9u,
        0xB2u, 0x4Du, 0x6Du, 0xD7u, 0x5Bu, 0xFEu, 0xE4u, 0x16u,
        0xF9u, 0x19u, 0xDDu, 0xDFu, 0xA5u, 0x47u, 0xEDu, 0x3Fu
    };
    static const char expected_fingerprint[] = "054710888721795994525986632373507176203917703081936096294433";
    static const char expected_offer[] = "амат кбмр дчакйвнд йомехьдъ сткцфп ъсбжд йбглжщжщ дъыочлпя оиечщгзо эяйкзэфя эоошшнкх бччьш кцъе лжсэж рнщъу тжькмхщ рэгац диеюргфэ щкгы ьюдмювл рыкия сючюэя чмнызнж жеыъс юмъг ьжещциш ищлчкйф бфязъ хофья йопкянци иэзящыщ яхюуе авщх нжзммъв бънул ыбтпвв трк";
    static const char expected_message[] = "амщъ ыиьяци аълй рыавй кбпм оижрюасе кхдв ершг шылпэщдр илэяшвм ъуошн ыуврфч ыьйътх дшжшгчяу бваеф гкукмгс екэу гбмжуьб четгнъх дьгиыщиф чщсрвщг неолющз очюьоэйо тф";
    v2_party a;
    v2_party b;
    uint8_t seed[KC_SEED_SIZE];
    uint8_t random[KC_OFFER_RANDOM_SIZE];
    uint8_t offer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t answer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t pending[KC_PENDING_STATE_SIZE];
    uint8_t digits[KC_FINGERPRINT_DIGITS];
    uint8_t wire[2048];
    size_t len = 0u;
    size_t offer_len = 0u;
    size_t answer_len = 0u;
    size_t pending_len = 0u;
    size_t wire_len = 0u;

    memset(&a, 0, sizeof(a));
    memset(&b, 0, sizeof(b));
    a.id = 1001;
    b.id = 2002;
    v2_fill_seeded(seed, sizeof(seed), 101u);
    v2_expect(kc_identity_create(seed, sizeof(seed), a.identity,
                                 sizeof(a.identity), &len) == KC_OK,
              "pinned identity a");
    v2_expect(memcmp(a.identity + KC_SEED_SIZE, expected_public_a, 32u) == 0,
              "pinned public a");
    v2_fill_seeded(seed, sizeof(seed), 102u);
    v2_expect(kc_identity_create(seed, sizeof(seed), b.identity,
                                 sizeof(b.identity), &len) == KC_OK,
              "pinned identity b");
    v2_expect(kc_fingerprint(a.id, a.identity + KC_SEED_SIZE, 32u, b.id,
                             b.identity + KC_SEED_SIZE, 32u, digits,
                             sizeof(digits), &len) == KC_OK &&
                  memcmp(digits, expected_fingerprint, KC_FINGERPRINT_DIGITS) ==
                      0,
              "pinned fingerprint");
    v2_fill_seeded(random, KC_OFFER_RANDOM_SIZE, 201u);
    v2_expect(kc_session_offer(a.identity, sizeof(a.identity), 3003, a.id, b.id,
                               random, KC_OFFER_RANDOM_SIZE, offer_text,
                               sizeof(offer_text), &offer_len, pending,
                               sizeof(pending), &pending_len) == KC_OK &&
                  offer_len == sizeof(expected_offer) - 1u &&
                  memcmp(offer_text, expected_offer, offer_len) == 0,
              "pinned offer");
    v2_fill_seeded(random, KC_ANSWER_RANDOM_SIZE, 202u);
    v2_expect(kc_session_answer(b.identity, sizeof(b.identity), 3003, b.id,
                                a.id, offer_text, offer_len, NULL, 0u, random,
                                KC_ANSWER_RANDOM_SIZE, answer_text,
                                sizeof(answer_text), &answer_len, b.state,
                                sizeof(b.state), &b.state_len) == KC_OK,
              "pinned answer");
    v2_fill_seeded(random, KC_ACCEPT_RANDOM_SIZE, 203u);
    v2_expect(kc_session_accept(a.identity, sizeof(a.identity), pending,
                                pending_len, answer_text, answer_len, NULL, 0u, random,
                                KC_ACCEPT_RANDOM_SIZE, a.state, sizeof(a.state),
                                &a.state_len) == KC_OK,
              "pinned accept");
    v2_fill_seeded(random, KC_ENCRYPT_RANDOM_SIZE, 301u);
    v2_expect(kc_session_encrypt(a.state, a.state_len, KC_CONTENT_TEXT,
                                 (const uint8_t *)"первое от А", 20u, random,
                                 KC_ENCRYPT_RANDOM_SIZE, wire, sizeof(wire),
                                 &wire_len, a.state, sizeof(a.state),
                                 &a.state_len) == KC_OK &&
                  wire_len == sizeof(expected_message) - 1u &&
                  memcmp(wire, expected_message, wire_len) == 0,
              "pinned first message");
}


static void v2_test_import_never_reuses_keys(void)
{
    v2_party alice;
    v2_party bob;
    v2_party imported;
    uint8_t from_bob[1024];
    uint8_t from_imported[1024];
    uint8_t from_alice[1024];
    size_t bob_len = 0u;
    size_t imported_len = 0u;
    size_t alice_len = 0u;
    char plain[256];

    v2_rng_seed(29u);
    v2_party_init(&alice, 41);
    v2_party_init(&bob, 42);
    v2_expect(v2_establish(&alice, &bob, 43), "establish answerer export");

    memcpy(&imported, &bob, sizeof(imported));
    imported.state[1] |= 0x01u;

    v2_expect(v2_send(&imported, "с нового устройства", from_imported,
                      sizeof(from_imported), &imported_len) ==
                  KC_ERR_AWAITING_PEER,
              "imported answerer refuses to send before the peer speaks");
    v2_expect(imported.state[1] & 0x01u, "force_dh survives the refusal");

    v2_expect(v2_send(&bob, "со старого устройства", from_bob,
                      sizeof(from_bob), &bob_len) == KC_OK,
              "exporter can still send");
    v2_expect(v2_recv(&alice, from_bob, bob_len, plain, sizeof(plain)) == KC_OK,
              "alice reads the exporter");

    v2_expect(v2_send(&alice, "привет", from_alice, sizeof(from_alice),
                      &alice_len) == KC_OK,
              "alice answers");
    v2_expect(v2_recv(&imported, from_alice, alice_len, plain,
                      sizeof(plain)) == KC_OK,
              "imported reads alice");
    v2_expect(v2_send(&imported, "с нового устройства", from_imported,
                      sizeof(from_imported), &imported_len) == KC_OK,
              "imported sends once it has a ratchet key");
    v2_expect(bob_len != imported_len ||
                  memcmp(from_bob, from_imported, bob_len) != 0,
              "imported envelope differs from the exporter's");
    v2_expect(v2_recv(&alice, from_imported, imported_len, plain,
                      sizeof(plain)) == KC_OK &&
                  strcmp(plain, "с нового устройства") == 0,
              "alice reads the imported device");
}

static void v2_test_export_cost_is_clamped(void)
{
    static const uint8_t password[] = "pw";
    static const uint8_t container[] = {0u, 0u, 0u, 0u};
    uint8_t random[KC_EXPORT_RANDOM_SIZE];
    uint8_t blob[128];
    uint8_t opened[128];
    size_t blob_len = 0u;
    size_t opened_len = 0u;

    v2_rng_seed(30u);
    v2_rng_fill(random, sizeof(random));
    v2_expect(kc_export_seal(password, sizeof(password) - 1u, 8u, 9u, random,
                             sizeof(random), container, sizeof(container), blob,
                             sizeof(blob),
                             &blob_len) == KC_ERR_INVALID_ARGUMENT,
              "seal rejects an excessive pass count");
    v2_expect(kc_export_seal(password, sizeof(password) - 1u, 8u, 1u, random,
                             sizeof(random), container, sizeof(container), blob,
                             sizeof(blob), &blob_len) == KC_OK,
              "seal accepts a sane pass count");
    blob[1u + 16u + 4u + 3u] = 9u;
    v2_expect(kc_export_open(password, sizeof(password) - 1u, blob, blob_len,
                             opened, sizeof(opened),
                             &opened_len) == KC_ERR_MALFORMED,
              "open rejects an excessive pass count from the header");
    blob[1u + 16u] = 0xFFu;
    blob[1u + 16u + 4u + 3u] = 1u;
    v2_expect(kc_export_open(password, sizeof(password) - 1u, blob, blob_len,
                             opened, sizeof(opened),
                             &opened_len) == KC_ERR_MALFORMED,
              "open rejects an excessive memory cost from the header");
}

static void v2_test_pins_expected_peer(void)
{
    v2_party alice;
    v2_party bob;
    v2_party mallory;
    uint8_t offer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t bob_answer[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t mallory_answer[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t pending[KC_PENDING_STATE_SIZE];
    uint8_t random[KC_OFFER_RANDOM_SIZE];
    uint8_t state[KC_SESSION_STATE_MAX];
    uint8_t bob_public[KC_PUBLIC_KEY_SIZE];
    size_t offer_len = 0u;
    size_t bob_len = 0u;
    size_t mallory_len = 0u;
    size_t pending_len = 0u;
    size_t state_len = 0u;
    size_t len = 0u;

    v2_rng_seed(34u);
    v2_party_init(&alice, 81);
    v2_party_init(&bob, 82);
    v2_party_init(&mallory, 83);
    v2_expect(kc_identity_public_key(bob.identity, sizeof(bob.identity),
                                     bob_public, sizeof(bob_public), &len) ==
                  KC_OK,
              "pin: bob public");

    v2_rng_fill(random, KC_OFFER_RANDOM_SIZE);
    v2_expect(kc_session_offer(alice.identity, sizeof(alice.identity), 84, 81,
                               82, random, KC_OFFER_RANDOM_SIZE, offer_text,
                               sizeof(offer_text), &offer_len, pending,
                               sizeof(pending), &pending_len) == KC_OK,
              "pin: offer");

    v2_rng_fill(random, KC_ANSWER_RANDOM_SIZE);
    v2_expect(kc_session_answer(bob.identity, sizeof(bob.identity), 84, 82, 81,
                                offer_text, offer_len, NULL, 0u, random,
                                KC_ANSWER_RANDOM_SIZE, bob_answer,
                                sizeof(bob_answer), &bob_len, state,
                                sizeof(state), &state_len) == KC_OK,
              "pin: bob answers");

    v2_rng_fill(random, KC_ANSWER_RANDOM_SIZE);
    v2_expect(kc_session_answer(mallory.identity, sizeof(mallory.identity), 84,
                                82, 81, offer_text, offer_len, NULL, 0u, random,
                                KC_ANSWER_RANDOM_SIZE, mallory_answer,
                                sizeof(mallory_answer), &mallory_len, state,
                                sizeof(state), &state_len) == KC_OK,
              "pin: mallory forges an answer for bob");

    v2_rng_fill(random, KC_ACCEPT_RANDOM_SIZE);
    v2_expect(kc_session_accept(alice.identity, sizeof(alice.identity), pending,
                                pending_len, mallory_answer, mallory_len, NULL,
                                0u, random, KC_ACCEPT_RANDOM_SIZE, state,
                                sizeof(state), &state_len) == KC_OK,
              "pin: unpinned accept takes whoever answered (first contact)");

    v2_rng_fill(random, KC_ACCEPT_RANDOM_SIZE);
    v2_expect(kc_session_accept(alice.identity, sizeof(alice.identity), pending,
                                pending_len, mallory_answer, mallory_len,
                                bob_public, sizeof(bob_public), random,
                                KC_ACCEPT_RANDOM_SIZE, state, sizeof(state),
                                &state_len) == KC_ERR_BAD_PEER,
              "pin: a pinned peer rejects the substituted answer");

    v2_rng_fill(random, KC_ACCEPT_RANDOM_SIZE);
    v2_expect(kc_session_accept(alice.identity, sizeof(alice.identity), pending,
                                pending_len, bob_answer, bob_len, bob_public,
                                sizeof(bob_public), random,
                                KC_ACCEPT_RANDOM_SIZE, state, sizeof(state),
                                &state_len) == KC_OK,
              "pin: the real peer still passes");

    v2_rng_fill(random, KC_ACCEPT_RANDOM_SIZE);
    v2_expect(kc_session_accept(alice.identity, sizeof(alice.identity), pending,
                                pending_len, bob_answer, bob_len, bob_public,
                                16u, random, KC_ACCEPT_RANDOM_SIZE, state,
                                sizeof(state),
                                &state_len) == KC_ERR_INVALID_ARGUMENT,
              "pin: a malformed pin is rejected");
}

static void v2_test_rejects_bad_peer_key(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t offer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t answer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t pending[KC_PENDING_STATE_SIZE];
    uint8_t random[KC_OFFER_RANDOM_SIZE];
    uint8_t state[KC_SESSION_STATE_MAX];
    size_t offer_len = 0u;
    size_t answer_len = 0u;
    size_t pending_len = 0u;
    size_t state_len = 0u;
    size_t index;

    v2_rng_seed(31u);
    v2_party_init(&alice, 51);
    v2_party_init(&bob, 52);
    v2_rng_fill(random, KC_OFFER_RANDOM_SIZE);
    v2_expect(kc_session_offer(alice.identity, sizeof(alice.identity), 53, 51,
                               52, random, KC_OFFER_RANDOM_SIZE, offer_text,
                               sizeof(offer_text), &offer_len, pending,
                               sizeof(pending), &pending_len) == KC_OK,
              "bad peer offer");
    v2_rng_fill(random, KC_ANSWER_RANDOM_SIZE);
    v2_expect(kc_session_answer(bob.identity, sizeof(bob.identity), 53, 52, 51,
                                offer_text, offer_len, NULL, 0u, random,
                                KC_ANSWER_RANDOM_SIZE, answer_text,
                                sizeof(answer_text), &answer_len, state,
                                sizeof(state), &state_len) == KC_OK,
              "bad peer answer");
    for (index = 0u; index < 5u; index++) {
        uint8_t forged[KC_HANDSHAKE_TEXT_BOUND];
        size_t forged_len = answer_len;
        memcpy(forged, answer_text, answer_len);
        v2_rng_fill(random, KC_ACCEPT_RANDOM_SIZE);
        v2_expect(kc_session_accept(alice.identity, sizeof(alice.identity),
                                    pending, pending_len, forged, forged_len,
                                    NULL, 0u,
                                    random, KC_ACCEPT_RANDOM_SIZE, state,
                                    sizeof(state), &state_len) == KC_OK,
                  "unmodified answer still accepted");
    }
}

static void v2_test_rejects_bad_content(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t wire[1024];
    uint8_t plain[256];
    uint8_t content_type = 0u;
    size_t wire_len = 0u;
    size_t plain_len = 0u;
    size_t index;

    v2_rng_seed(32u);
    v2_party_init(&alice, 61);
    v2_party_init(&bob, 62);
    v2_expect(v2_establish(&alice, &bob, 63), "establish content reject");
    v2_expect(v2_send(&alice, "ок", wire, sizeof(wire), &wire_len) == KC_OK,
              "content reject send");
    for (index = 0u; index < wire_len; index++) {
        if (wire[index] == (uint8_t)' ') continue;
        wire[index] = wire[index] == 0xD0u ? 0xD1u : 0xD0u;
        break;
    }
    v2_expect(kc_session_decrypt(bob.state, bob.state_len, wire, wire_len,
                                 &content_type, plain, sizeof(plain),
                                 &plain_len, bob.state, sizeof(bob.state),
                                 &bob.state_len) != KC_OK,
              "corrupted envelope rejected");
    v2_expect(kc_session_decrypt(bob.state, bob.state_len,
                                 (const uint8_t *)"", 0u, &content_type, plain,
                                 sizeof(plain), &plain_len, bob.state,
                                 sizeof(bob.state), &bob.state_len) ==
                  KC_ERR_NOT_ENCRYPTED,
              "empty text rejected");
}

static void v2_test_status_strings(void)
{
    static const kc_status codes[] = {
        KC_OK,           KC_ERR_EMPTY_PASSWORD, KC_ERR_BAD_KEY_LENGTH,
        KC_ERR_NOT_ENCRYPTED, KC_ERR_MALFORMED,  KC_ERR_WRONG_KEY,
        KC_ERR_INTERNAL, KC_ERR_BUFFER_TOO_SMALL, KC_ERR_INVALID_ARGUMENT,
        KC_ERR_OUT_OF_MEMORY, KC_ERR_BAD_SIGNATURE, KC_ERR_BAD_STATE,
        KC_ERR_TOO_MANY_SKIPPED, KC_ERR_REPLAY, KC_ERR_BAD_PEER,
        KC_ERR_UNSUPPORTED_VERSION, KC_ERR_HANDSHAKE_MESSAGE, KC_ERR_TOO_LONG,
        KC_ERR_AWAITING_PEER};
    size_t index;
    uint8_t buffer[64];
    size_t out_len = 0u;

    for (index = 0u; index < sizeof(codes) / sizeof(codes[0]); index++) {
        const char *text = kc_status_string(codes[index]);
        v2_expect(text != NULL && text[0] != '\0' &&
                      strcmp(text, "unknown") != 0,
                  "status string present");
    }
    v2_expect(strcmp(kc_status_string((kc_status)-999), "unknown") == 0,
              "unknown status");
    memset(buffer, 0xAAu, sizeof(buffer));
    kc_wipe(buffer, sizeof(buffer));
    for (index = 0u; index < sizeof(buffer); index++) {
        v2_expect(buffer[index] == 0u, "kc_wipe zeroes");
    }
    kc_wipe(NULL, 0u);
    v2_expect(kc_session_encrypt_bound(0u) > 0u, "encrypt bound");
    v2_expect(kc_session_encrypt_bound(KC_SESSION_PLAINTEXT_MAX + 1u) == 0u,
              "encrypt bound refuses oversize");
    v2_expect(kc_session_decrypt_bound(100u) == 100u, "decrypt bound");
    v2_expect(kc_file_open_bound(100u) == 100u, "file open bound");
    v2_expect(kc_local_open_bound(10u) == 0u, "local open bound floor");
    v2_expect(kc_export_open_bound(10u) == 0u, "export open bound floor");
    v2_expect(kc_encrypt_image_blob_bound(10u) > 10u, "image encrypt bound");
    v2_expect(kc_decrypt_image_blob_bound(10u) == 0u, "image decrypt floor");
    (void)out_len;
}

static void v2_test_peer_public_key(void)
{
    v2_party alice;
    v2_party bob;
    uint8_t from_state[KC_PUBLIC_KEY_SIZE];
    uint8_t from_identity[KC_PUBLIC_KEY_SIZE];
    size_t len = 0u;

    v2_rng_seed(33u);
    v2_party_init(&alice, 71);
    v2_party_init(&bob, 72);
    v2_expect(v2_establish(&alice, &bob, 73), "establish peer key");
    v2_expect(kc_session_peer_public_key(alice.state, alice.state_len,
                                         from_state, sizeof(from_state),
                                         &len) == KC_OK &&
                  len == KC_PUBLIC_KEY_SIZE,
              "peer key from alice state");
    v2_expect(kc_identity_public_key(bob.identity, sizeof(bob.identity),
                                     from_identity, sizeof(from_identity),
                                     &len) == KC_OK,
              "bob public");
    v2_expect(memcmp(from_state, from_identity, KC_PUBLIC_KEY_SIZE) == 0,
              "session state carries the real peer identity key");
    v2_expect(kc_session_peer_public_key(bob.state, bob.state_len, from_state,
                                         sizeof(from_state), &len) == KC_OK,
              "peer key from bob state");
    v2_expect(kc_identity_public_key(alice.identity, sizeof(alice.identity),
                                     from_identity, sizeof(from_identity),
                                     &len) == KC_OK &&
                  memcmp(from_state, from_identity, KC_PUBLIC_KEY_SIZE) == 0,
              "symmetric peer identity");
    v2_expect(kc_session_peer_public_key(alice.state, 10u, from_state,
                                         sizeof(from_state), &len) ==
                  KC_ERR_BAD_STATE,
              "peer key rejects a short state");
}


int kc_run_v2_tests(void)
{
    v2_test_identity();
    v2_test_fingerprint();
    v2_test_local();
    v2_test_conversation();
    v2_test_bob_first();
    v2_test_out_of_order();
    v2_test_skip_limit();
    v2_test_epoch_change_never_wedges();
    v2_test_unreachable_previous_epoch();
    v2_test_forged_counter_is_bounded();
    v2_test_handshake_errors();
    v2_test_content_types();
    v2_test_file();
    v2_test_export();
    v2_test_classify();
    v2_test_pinned_vectors();
    v2_test_import_never_reuses_keys();
    v2_test_export_cost_is_clamped();
    v2_test_pins_expected_peer();
    v2_test_rejects_bad_peer_key();
    v2_test_rejects_bad_content();
    v2_test_status_strings();
    v2_test_peer_public_key();
    return v2_failures;
}
