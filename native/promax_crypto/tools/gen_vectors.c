#include "promax_crypto.h"

#include "monocypher.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *seed_dir;

static void emit_seed(unsigned char op, const void *bytes, size_t len)
{
    char path[512];
    static unsigned int counter;
    FILE *fh;

    if (seed_dir == NULL) {
        return;
    }
    snprintf(path, sizeof(path), "%s/seed_%02u_%u", seed_dir, (unsigned int)op,
             counter++);
    fh = fopen(path, "wb");
    if (fh == NULL) {
        return;
    }
    fputc((int)op, fh);
    fwrite(bytes, 1u, len, fh);
    fclose(fh);
}

static void fill(uint8_t *out, size_t len, uint64_t seed)
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

static void print_hex(const char *key, const uint8_t *bytes, size_t len)
{
    size_t index;

    printf("\"%s\": \"", key);
    for (index = 0u; index < len; index++) {
        printf("%02x", bytes[index]);
    }
    printf("\"");
}

static void print_text(const char *key, const uint8_t *text, size_t len)
{
    printf("\"%s\": \"", key);
    fwrite(text, 1u, len, stdout);
    printf("\"");
}

static void must(kc_status status, const char *what)
{
    if (status != KC_OK) {
        fprintf(stderr, "%s: %s\n", what, kc_status_string(status));
        exit(1);
    }
}

typedef struct {
    int64_t id;
    uint8_t identity[KC_IDENTITY_SIZE];
    uint8_t state[KC_SESSION_STATE_MAX];
    size_t state_len;
} party;

static void emit_message(party *from,
                         party *to,
                         const char *plaintext,
                         uint64_t seed,
                         int comma)
{
    uint8_t random[KC_ENCRYPT_RANDOM_SIZE];
    uint8_t text[2048];
    uint8_t opened[512];
    uint8_t content_type = 0u;
    size_t text_len = 0u;
    size_t opened_len = 0u;

    fill(random, sizeof(random), seed);
    must(kc_session_encrypt(from->state, from->state_len, KC_CONTENT_TEXT,
                            (const uint8_t *)plaintext, strlen(plaintext),
                            random, sizeof(random), text, sizeof(text),
                            &text_len, from->state, sizeof(from->state),
                            &from->state_len),
         "encrypt");
    must(kc_session_decrypt(to->state, to->state_len, text, text_len,
                            &content_type, opened, sizeof(opened), &opened_len,
                            to->state, sizeof(to->state), &to->state_len),
         "decrypt");
    if (opened_len != strlen(plaintext) ||
        memcmp(opened, plaintext, opened_len) != 0) {
        fprintf(stderr, "vector mismatch\n");
        exit(1);
    }
    printf("    {\"from\": \"%s\", ", from->id < to->id ? "a" : "b");
    print_hex("random", random, sizeof(random));
    printf(", \"content_type\": 1, ");
    print_text("plaintext", (const uint8_t *)plaintext, strlen(plaintext));
    printf(", ");
    print_text("text", text, text_len);
    printf(", ");
    print_hex("sender_state_after", from->state, from->state_len);
    printf(", ");
    print_hex("receiver_state_after", to->state, to->state_len);
    printf("}%s\n", comma ? "," : "");
}

int main(int argc, char **argv)
{
    party a;
    party b;
    uint8_t seed[KC_SEED_SIZE];
    uint8_t public_a[KC_PUBLIC_KEY_SIZE];
    uint8_t public_b[KC_PUBLIC_KEY_SIZE];
    uint8_t x_public_a[32];
    uint8_t random[KC_OFFER_RANDOM_SIZE];
    uint8_t offer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t answer_text[KC_HANDSHAKE_TEXT_BOUND];
    uint8_t pending[KC_PENDING_STATE_SIZE];
    uint8_t digits[KC_FINGERPRINT_DIGITS];
    uint8_t local_key[KC_LOCAL_KEY_SIZE];
    uint8_t local_nonce[KC_LOCAL_NONCE_SIZE];
    uint8_t local_blob[128];
    uint8_t file_key[KC_FILE_KEY_SIZE];
    uint8_t file_nonce[KC_FILE_NONCE_SIZE];
    uint8_t file_ctx[KC_FILE_CTX_SIZE];
    uint8_t *file_plain;
    uint8_t *file_cipher;
    uint8_t file_hash[32];
    uint8_t container[4096];
    uint8_t export_random[KC_EXPORT_RANDOM_SIZE];
    uint8_t export_blob[4096];
    uint8_t opened[4096];
    uint8_t skipped_text[2048];
    uint8_t content_type = 0u;
    size_t len = 0u;
    size_t offer_len = 0u;
    size_t answer_len = 0u;
    size_t pending_len = 0u;
    size_t file_len = 131073u;
    size_t cipher_len = 0u;
    size_t offset;
    size_t container_len;
    size_t export_len = 0u;
    size_t opened_len = 0u;
    size_t skipped_len = 0u;
    static const uint8_t local_aad[] = "session/1001/3003";
    static const uint8_t local_plain[] = "local plaintext";
    static const uint8_t password[] = "перенос";
    size_t index;

    if (argc == 3 && strcmp(argv[1], "--seed-corpus") == 0) {
        seed_dir = argv[2];
    }

    memset(&a, 0, sizeof(a));
    memset(&b, 0, sizeof(b));
    a.id = 1001;
    b.id = 2002;
    printf("{\n  \"version\": 3,\n");

    fill(seed, sizeof(seed), 101u);
    must(kc_identity_create(seed, sizeof(seed), a.identity, sizeof(a.identity),
                            &len),
         "identity a");
    printf("  \"identity_a\": {");
    print_hex("seed", seed, sizeof(seed));
    printf(", ");
    print_hex("identity", a.identity, sizeof(a.identity));
    must(kc_identity_public_key(a.identity, sizeof(a.identity), public_a,
                                sizeof(public_a), &len),
         "public a");
    printf(", ");
    print_hex("public", public_a, sizeof(public_a));
    crypto_eddsa_to_x25519(x_public_a, public_a);
    printf(", ");
    print_hex("x25519_public", x_public_a, sizeof(x_public_a));
    printf("},\n");

    fill(seed, sizeof(seed), 102u);
    must(kc_identity_create(seed, sizeof(seed), b.identity, sizeof(b.identity),
                            &len),
         "identity b");
    must(kc_identity_public_key(b.identity, sizeof(b.identity), public_b,
                                sizeof(public_b), &len),
         "public b");
    printf("  \"identity_b\": {");
    print_hex("seed", seed, sizeof(seed));
    printf(", ");
    print_hex("identity", b.identity, sizeof(b.identity));
    printf(", ");
    print_hex("public", public_b, sizeof(public_b));
    printf("},\n");

    must(kc_fingerprint(a.id, public_a, sizeof(public_a), b.id, public_b,
                        sizeof(public_b), digits, sizeof(digits), &len),
         "fingerprint");
    printf("  ");
    print_text("fingerprint", digits, sizeof(digits));
    printf(",\n");

    printf("  \"handshake\": {\"chat_id\": 3003, \"a_id\": 1001, \"b_id\": 2002,\n");
    fill(random, KC_OFFER_RANDOM_SIZE, 201u);
    must(kc_session_offer(a.identity, sizeof(a.identity), 3003, a.id, b.id,
                          random, KC_OFFER_RANDOM_SIZE, offer_text,
                          sizeof(offer_text), &offer_len, pending,
                          sizeof(pending), &pending_len),
         "offer");
    printf("    ");
    print_hex("offer_random", random, KC_OFFER_RANDOM_SIZE);
    printf(",\n    ");
    print_text("offer_text", offer_text, offer_len);
    emit_seed(0u, offer_text, offer_len);
    emit_seed(9u, offer_text, offer_len);
    emit_seed(4u, offer_text, offer_len);
    printf(",\n    ");
    print_hex("pending", pending, pending_len);
    printf(",\n");
    fill(random, KC_ANSWER_RANDOM_SIZE, 202u);
    must(kc_session_answer(b.identity, sizeof(b.identity), 3003, b.id, a.id,
                           offer_text, offer_len, NULL, 0u, random,
                           KC_ANSWER_RANDOM_SIZE, answer_text,
                           sizeof(answer_text), &answer_len, b.state,
                           sizeof(b.state), &b.state_len),
         "answer");
    printf("    ");
    print_hex("answer_random", random, KC_ANSWER_RANDOM_SIZE);
    printf(",\n    ");
    print_text("answer_text", answer_text, answer_len);
    emit_seed(9u, answer_text, answer_len);
    emit_seed(5u, answer_text, answer_len);
    emit_seed(3u, b.state, b.state_len);
    printf(",\n    ");
    print_hex("b_state_after_answer", b.state, b.state_len);
    printf(",\n");
    fill(random, KC_ACCEPT_RANDOM_SIZE, 203u);
    must(kc_session_accept(a.identity, sizeof(a.identity), pending, pending_len,
                           answer_text, answer_len, NULL, 0u, random,
                           KC_ACCEPT_RANDOM_SIZE, a.state, sizeof(a.state),
                           &a.state_len),
         "accept");
    printf("    ");
    print_hex("accept_random", random, KC_ACCEPT_RANDOM_SIZE);
    printf(",\n    ");
    print_hex("a_state_after_accept", a.state, a.state_len);
    printf("\n  },\n");

    printf("  \"messages\": [\n");
    emit_message(&a, &b, "первое от А", 301u, 1);
    emit_message(&a, &b, "второе от А", 302u, 1);
    emit_message(&b, &a, "ответ от Б", 303u, 1);
    emit_message(&a, &b, "новая эпоха", 304u, 1);
    fill(random, KC_ENCRYPT_RANDOM_SIZE, 305u);
    must(kc_session_encrypt(a.state, a.state_len, KC_CONTENT_TEXT,
                            (const uint8_t *)"пропущенное", 22u, random,
                            KC_ENCRYPT_RANDOM_SIZE, skipped_text,
                            sizeof(skipped_text), &skipped_len, a.state,
                            sizeof(a.state), &a.state_len),
         "skipped encrypt");
    emit_seed(1u, skipped_text, skipped_len);
    emit_seed(2u, skipped_text, skipped_len);
    emit_seed(0u, skipped_text, skipped_len);
    printf("    {\"from\": \"a\", ");
    print_hex("random", random, KC_ENCRYPT_RANDOM_SIZE);
    printf(", \"content_type\": 1, ");
    print_text("plaintext", (const uint8_t *)"пропущенное", 22u);
    printf(", ");
    print_text("text", skipped_text, skipped_len);
    printf(", \"delivered_later\": true, ");
    print_hex("sender_state_after", a.state, a.state_len);
    printf("},\n");
    emit_message(&a, &b, "после пропуска", 306u, 1);
    must(kc_session_decrypt(b.state, b.state_len, skipped_text, skipped_len,
                            &content_type, opened, sizeof(opened), &opened_len,
                            b.state, sizeof(b.state), &b.state_len),
         "skipped decrypt");
    printf("    {\"from\": \"a\", \"replay_of\": 4, ");
    print_hex("receiver_state_after", b.state, b.state_len);
    printf("}\n  ],\n");

    fill(local_key, sizeof(local_key), 401u);
    fill(local_nonce, sizeof(local_nonce), 402u);
    must(kc_local_seal(local_key, sizeof(local_key), local_nonce,
                       sizeof(local_nonce), local_aad, sizeof(local_aad) - 1u,
                       local_plain, sizeof(local_plain) - 1u, local_blob,
                       sizeof(local_blob), &len),
         "local seal");
    printf("  \"local\": {");
    print_hex("key", local_key, sizeof(local_key));
    printf(", ");
    print_hex("nonce", local_nonce, sizeof(local_nonce));
    printf(", ");
    print_text("aad", local_aad, sizeof(local_aad) - 1u);
    printf(", ");
    print_text("plaintext", local_plain, sizeof(local_plain) - 1u);
    emit_seed(8u, local_blob, len);
    printf(", ");
    print_hex("blob", local_blob, len);
    printf("},\n");

    fill(file_key, sizeof(file_key), 501u);
    fill(file_nonce, sizeof(file_nonce), 502u);
    file_plain = (uint8_t *)malloc(file_len);
    file_cipher = (uint8_t *)malloc(kc_file_seal_bound(file_len));
    for (index = 0u; index < file_len; index++) {
        file_plain[index] = (uint8_t)((index * 7u + 3u) & 0xFFu);
    }
    must(kc_file_seal_init(file_ctx, sizeof(file_ctx), file_key,
                           sizeof(file_key), file_nonce, sizeof(file_nonce)),
         "file init");
    offset = 0u;
    for (;;) {
        size_t take = file_len - offset < KC_FILE_CHUNK_SIZE
                          ? file_len - offset
                          : KC_FILE_CHUNK_SIZE;
        int last = file_len - offset <= KC_FILE_CHUNK_SIZE;
        must(kc_file_seal_chunk(file_ctx, sizeof(file_ctx), file_plain + offset,
                                take, last, file_cipher + cipher_len,
                                take + KC_TAG_SIZE, &len),
             "file chunk");
        cipher_len += len;
        offset += take;
        if (last) {
            break;
        }
    }
    crypto_blake2b(file_hash, sizeof(file_hash), file_cipher, cipher_len);
    printf("  \"file\": {");
    print_hex("key", file_key, sizeof(file_key));
    printf(", ");
    print_hex("nonce", file_nonce, sizeof(file_nonce));
    printf(", \"plaintext_len\": %u, \"plaintext_rule\": \"byte[i] = (i * 7 + 3) & 0xff\", \"ciphertext_len\": %u, ",
           (unsigned int)file_len, (unsigned int)cipher_len);
    emit_seed(6u, file_cipher, KC_FILE_CHUNK_SIZE + KC_TAG_SIZE);
    print_hex("ciphertext_head", file_cipher, 64u);
    printf(", ");
    print_hex("ciphertext_blake2b256", file_hash, sizeof(file_hash));
    printf("},\n");
    free(file_plain);
    free(file_cipher);

    memset(container, 0, sizeof(container));
    container[3] = 2u;
    offset = 4u;
    container[offset + 3u] = (uint8_t)KC_IDENTITY_SIZE;
    offset += 4u;
    memcpy(container + offset, a.identity, KC_IDENTITY_SIZE);
    offset += KC_IDENTITY_SIZE;
    container[offset + 2u] = (uint8_t)(a.state_len >> 8u);
    container[offset + 3u] = (uint8_t)a.state_len;
    offset += 4u;
    memcpy(container + offset, a.state, a.state_len);
    offset += a.state_len;
    container_len = offset;
    fill(export_random, sizeof(export_random), 601u);
    must(kc_export_seal(password, sizeof(password) - 1u, 8u, 1u, export_random,
                        sizeof(export_random), container, container_len,
                        export_blob, sizeof(export_blob), &export_len),
         "export seal");
    must(kc_export_open(password, sizeof(password) - 1u, export_blob,
                        export_len, opened, sizeof(opened), &opened_len),
         "export open");
    printf("  \"export\": {");
    print_text("password", password, sizeof(password) - 1u);
    printf(", \"memory_kib\": 8, \"passes\": 1, ");
    print_hex("random", export_random, sizeof(export_random));
    printf(", ");
    print_hex("container", container, container_len);
    emit_seed(7u, export_blob, export_len);
    printf(", ");
    print_hex("blob", export_blob, export_len);
    printf(", ");
    print_hex("opened_container", opened, opened_len);
    printf("}\n}\n");
    return 0;
}
