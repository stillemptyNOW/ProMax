#include "promax_crypto.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

int kc_run_v2_tests(void);

static void expect(int condition, const char *name)
{
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", name);
        failures++;
    }
}

static int hex_value(char value)
{
    if (value >= '0' && value <= '9') {
        return value - '0';
    }
    return value - 'a' + 10;
}

static void decode_hex(const char *text, uint8_t *out, size_t out_len)
{
    size_t index;
    for (index = 0u; index < out_len; index++) {
        out[index] = (uint8_t)((hex_value(text[index * 2u]) << 4) |
                               hex_value(text[index * 2u + 1u]));
    }
}

static void test_derive_key(void)
{
    static const uint8_t password[] = "fixture-password-01";
    static const char expected_hex[] =
        "a8e95a06e19c14f1d33a3d328e368ab7962cc1a7c9c00939d1ffadd871775164";
    uint8_t expected[KC_KEY_SIZE];
    uint8_t actual[KC_KEY_SIZE];
    kc_status status;

    decode_hex(expected_hex, expected, sizeof(expected));
    status = kc_derive_key(password, sizeof(password) - 1u, actual,
                           sizeof(actual));
    expect(status == KC_OK, "derive status");
    expect(memcmp(actual, expected, sizeof(actual)) == 0, "derive vector");
    expect(kc_derive_key(password, 0u, actual, sizeof(actual)) ==
               KC_ERR_EMPTY_PASSWORD,
           "derive empty");
}

static void test_message(void)
{
    static const uint8_t plaintext[] = "fixture-message-01";
    static const char expected_hex[] =
        "d0b9d0bcd0b0d18020d0b2d0b3d0b0d187d0b4d0b820d186d183d180d180d18a"
        "d0be20d0bbd0b5d182d0b6d18e20d18ed180d186d0b820d0b7d189d181d18ed0b7"
        "d18820d189d0b8d0bcd18c20d0bed0b3d0bdd180d0b0d187d181d18f20d185d0b6"
        "d0bcd182d0ba20d18ed0bcd0bfd18120d0bfd0bfd0b7d18620d0b9d0b6d0b2d187"
        "d18fd182d184d0b720d0bad18ed185d18c20d181d0b2d18fd0b7d0b0d18520d188"
        "d0b5d0b4";
    uint8_t key[KC_KEY_SIZE];
    uint8_t other_key[KC_KEY_SIZE];
    uint8_t nonce[KC_NONCE_SIZE];
    uint8_t expected[(sizeof(expected_hex) - 1u) / 2u];
    uint8_t *encrypted;
    uint8_t *decrypted;
    size_t encrypted_cap;
    size_t encrypted_len = 0u;
    size_t decrypted_len = 0u;
    size_t index;
    kc_status status;

    for (index = 0u; index < sizeof(key); index++) {
        key[index] = (uint8_t)(index * 7u + 3u);
        other_key[index] = (uint8_t)(key[index] ^ 0x5Au);
    }
    for (index = 0u; index < sizeof(nonce); index++) {
        nonce[index] = (uint8_t)(index * 11u + 1u);
    }
    decode_hex(expected_hex, expected, sizeof(expected));
    encrypted_cap = kc_encrypt_message_bound(sizeof(plaintext) - 1u);
    encrypted = (uint8_t *)malloc(encrypted_cap);
    decrypted = (uint8_t *)malloc(kc_decrypt_message_bound(encrypted_cap));
    expect(encrypted != NULL && decrypted != NULL, "message allocation");
    if (encrypted == NULL || decrypted == NULL) {
        free(encrypted);
        free(decrypted);
        return;
    }
    status = kc_encrypt_message(
        plaintext, sizeof(plaintext) - 1u, key, sizeof(key), nonce,
        sizeof(nonce), encrypted, encrypted_cap, &encrypted_len);
    expect(status == KC_OK, "message encrypt");
    expect(encrypted_len == sizeof(expected), "message vector length");
    expect(memcmp(encrypted, expected, sizeof(expected)) == 0,
           "message vector");
    expect(kc_looks_encrypted_message(encrypted, encrypted_len),
           "message detection");
    status = kc_decrypt_message(encrypted, encrypted_len, key, sizeof(key),
                                decrypted, encrypted_cap, &decrypted_len);
    expect(status == KC_OK, "message decrypt");
    expect(decrypted_len == sizeof(plaintext) - 1u,
           "message plaintext length");
    expect(memcmp(decrypted, plaintext, decrypted_len) == 0,
           "message plaintext");
    status = kc_decrypt_message(encrypted, encrypted_len, other_key,
                                sizeof(other_key), decrypted, encrypted_cap,
                                &decrypted_len);
    expect(status == KC_ERR_WRONG_KEY, "message wrong key");
    expect(!kc_looks_encrypted_message((const uint8_t *)"fixture", 7u),
           "message plain detection");
    free(encrypted);
    free(decrypted);
}

static void test_rust_message_vector(void)
{
    static const char encrypted_hex[] =
        "d0b9d0bcd0b0d18320d187d0b7d0b9d18bd186d18fd18d20d183d0bad18fd184"
        "d0bcd0b5d0bed0b820d0b9d186d0b0d0bdd18bd18dd188d18220d0b6d185d181"
        "d180d0b620d18fd180d0bfd186d18020d189d183d0bad0b720d183d183d0b3d183"
        "d0bcd187d0b5d0b120d0bbd0b2d181d185d18820d189d180d188d0b520d18cd0b4"
        "d0b7d184d0b7d187d0ba20d185d182d185d18bd18120d189d0bfd18bd0b820d183"
        "d187d184d185d185d184d0b3d18520d0b6d188d185d0bed0bd20d181";
    static const uint8_t plaintext[] = "fixture-message-from-rust";
    uint8_t encrypted[(sizeof(encrypted_hex) - 1u) / 2u];
    uint8_t decrypted[sizeof(plaintext)];
    uint8_t key[KC_KEY_SIZE];
    size_t decrypted_len = 0u;
    size_t index;
    kc_status status;

    decode_hex(encrypted_hex, encrypted, sizeof(encrypted));
    for (index = 0u; index < sizeof(key); index++) {
        key[index] = (uint8_t)(index * 7u + 3u);
    }
    status = kc_decrypt_message(encrypted, sizeof(encrypted), key, sizeof(key),
                                decrypted, sizeof(decrypted), &decrypted_len);
    expect(status == KC_OK, "rust vector decrypt");
    expect(decrypted_len == sizeof(plaintext) - 1u,
           "rust vector plaintext length");
    expect(memcmp(decrypted, plaintext, decrypted_len) == 0,
           "rust vector plaintext");
}

static void test_message_whitespace(void)
{
    static const uint8_t plaintext[] = "fixture-message-02";
    uint8_t key[KC_KEY_SIZE] = {0u};
    uint8_t nonce[KC_NONCE_SIZE] = {0u};
    uint8_t encrypted[256];
    uint8_t compact[256];
    uint8_t decrypted[256];
    size_t encrypted_len = 0u;
    size_t compact_len = 0u;
    size_t decrypted_len = 0u;
    size_t index;
    kc_status status;

    status = kc_encrypt_message(plaintext, sizeof(plaintext) - 1u, key,
                                sizeof(key), nonce, sizeof(nonce), encrypted,
                                sizeof(encrypted), &encrypted_len);
    expect(status == KC_OK, "whitespace encrypt");
    for (index = 0u; index < encrypted_len; index++) {
        if (encrypted[index] != (uint8_t)' ') {
            compact[compact_len++] = encrypted[index];
        }
    }
    status = kc_decrypt_message(compact, compact_len, key, sizeof(key),
                                decrypted, sizeof(decrypted), &decrypted_len);
    expect(status == KC_OK, "whitespace decrypt");
    expect(decrypted_len == sizeof(plaintext) - 1u &&
               memcmp(decrypted, plaintext, decrypted_len) == 0,
           "whitespace plaintext");
}

static void test_image_blob(void)
{
    static const char expected_hex[] =
        "4b020000006502070c11161b20252a2f34396de568dde4b8dad019643fcd8e3ae3"
        "c8679fde726c273de373cf6da15530341e0774ff422257dce47fe8e050ea0923d8"
        "c3406fe2644dad0aa3b3954e45e87de9bbe54b40921a8927be100eb73f4e3cd30"
        "b69c9eb64ffddc7e1";
    uint8_t plaintext[73];
    uint8_t key[KC_KEY_SIZE];
    uint8_t nonce[KC_NONCE_SIZE];
    uint8_t encrypted[128];
    uint8_t padded[137];
    uint8_t decrypted[73];
    uint8_t expected[(sizeof(expected_hex) - 1u) / 2u];
    size_t encrypted_len = 0u;
    size_t decrypted_len = 0u;
    size_t index;
    kc_status status;

    for (index = 0u; index < sizeof(plaintext); index++) {
        plaintext[index] = (uint8_t)(index * 13u + 5u);
    }
    for (index = 0u; index < sizeof(key); index++) {
        key[index] = (uint8_t)(index * 3u + 9u);
    }
    for (index = 0u; index < sizeof(nonce); index++) {
        nonce[index] = (uint8_t)(index * 5u + 2u);
    }
    decode_hex(expected_hex, expected, sizeof(expected));
    status = kc_encrypt_image_blob(
        plaintext, sizeof(plaintext), key, sizeof(key), nonce, sizeof(nonce),
        encrypted, sizeof(encrypted), &encrypted_len);
    expect(status == KC_OK, "image encrypt");
    expect(encrypted_len == sizeof(expected), "image vector length");
    expect(memcmp(encrypted, expected, sizeof(expected)) == 0,
           "image vector");
    memcpy(padded, encrypted, encrypted_len);
    memset(padded + encrypted_len, 0xA5, sizeof(padded) - encrypted_len);
    expect(kc_looks_encrypted_image_blob(padded, sizeof(padded)),
           "image detection");
    status = kc_decrypt_image_blob(padded, sizeof(padded), key, sizeof(key),
                                   decrypted, sizeof(decrypted),
                                   &decrypted_len);
    expect(status == KC_OK, "image decrypt");
    expect(decrypted_len == sizeof(plaintext), "image plaintext length");
    expect(memcmp(decrypted, plaintext, sizeof(plaintext)) == 0,
           "image plaintext");
    padded[6u + KC_NONCE_SIZE + 3u] ^= 1u;
    status = kc_decrypt_image_blob(padded, sizeof(padded), key, sizeof(key),
                                   decrypted, sizeof(decrypted),
                                   &decrypted_len);
    expect(status == KC_ERR_WRONG_KEY, "image tamper");
}

int main(void)
{
    test_derive_key();
    test_message();
    test_rust_message_vector();
    test_message_whitespace();
    test_image_blob();
    failures += kc_run_v2_tests();
    if (failures != 0) {
        fprintf(stderr, "%d failures\n", failures);
        return 1;
    }
    puts("ok");
    return 0;
}
