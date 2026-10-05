#include "kc_sha256.h"

#include "monocypher.h"

#include <string.h>

static const uint32_t kc_sha256_constants[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu,
    0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u, 0xd807aa98u, 0x12835b01u,
    0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u,
    0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u,
    0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u,
    0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
    0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u,
    0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u, 0x1e376c08u,
    0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu,
    0x682e6ff3u, 0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

static uint32_t kc_rotr32(uint32_t value, unsigned int count)
{
    return (value >> count) | (value << (32u - count));
}

static uint32_t kc_choose(uint32_t x, uint32_t y, uint32_t z)
{
    return (x & y) ^ (~x & z);
}

static uint32_t kc_majority(uint32_t x, uint32_t y, uint32_t z)
{
    return (x & y) ^ (x & z) ^ (y & z);
}

static uint32_t kc_big_sigma0(uint32_t value)
{
    return kc_rotr32(value, 2u) ^ kc_rotr32(value, 13u) ^
           kc_rotr32(value, 22u);
}

static uint32_t kc_big_sigma1(uint32_t value)
{
    return kc_rotr32(value, 6u) ^ kc_rotr32(value, 11u) ^
           kc_rotr32(value, 25u);
}

static uint32_t kc_small_sigma0(uint32_t value)
{
    return kc_rotr32(value, 7u) ^ kc_rotr32(value, 18u) ^ (value >> 3u);
}

static uint32_t kc_small_sigma1(uint32_t value)
{
    return kc_rotr32(value, 17u) ^ kc_rotr32(value, 19u) ^ (value >> 10u);
}

static void kc_sha256_block(kc_sha256 *context, const uint8_t *block)
{
    uint32_t words[64];
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t d;
    uint32_t e;
    uint32_t f;
    uint32_t g;
    uint32_t h;
    size_t index;

    for (index = 0u; index < 16u; index++) {
        words[index] = ((uint32_t)block[index * 4u] << 24u) |
                       ((uint32_t)block[index * 4u + 1u] << 16u) |
                       ((uint32_t)block[index * 4u + 2u] << 8u) |
                       (uint32_t)block[index * 4u + 3u];
    }
    for (index = 16u; index < 64u; index++) {
        words[index] = kc_small_sigma1(words[index - 2u]) +
                       words[index - 7u] +
                       kc_small_sigma0(words[index - 15u]) +
                       words[index - 16u];
    }
    a = context->state[0];
    b = context->state[1];
    c = context->state[2];
    d = context->state[3];
    e = context->state[4];
    f = context->state[5];
    g = context->state[6];
    h = context->state[7];
    for (index = 0u; index < 64u; index++) {
        uint32_t first = h + kc_big_sigma1(e) + kc_choose(e, f, g) +
                         kc_sha256_constants[index] + words[index];
        uint32_t second = kc_big_sigma0(a) + kc_majority(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + first;
        d = c;
        c = b;
        b = a;
        a = first + second;
    }
    context->state[0] += a;
    context->state[1] += b;
    context->state[2] += c;
    context->state[3] += d;
    context->state[4] += e;
    context->state[5] += f;
    context->state[6] += g;
    context->state[7] += h;
    crypto_wipe(words, sizeof(words));
}

void kc_sha256_init(kc_sha256 *context)
{
    if (context == NULL) {
        return;
    }
    context->state[0] = 0x6a09e667u;
    context->state[1] = 0xbb67ae85u;
    context->state[2] = 0x3c6ef372u;
    context->state[3] = 0xa54ff53au;
    context->state[4] = 0x510e527fu;
    context->state[5] = 0x9b05688cu;
    context->state[6] = 0x1f83d9abu;
    context->state[7] = 0x5be0cd19u;
    context->length = 0u;
    context->buffered = 0u;
    memset(context->buffer, 0, sizeof(context->buffer));
}

void kc_sha256_update(kc_sha256 *context,
                      const uint8_t *input,
                      size_t input_len)
{
    size_t offset = 0u;

    if (context == NULL || (input == NULL && input_len != 0u)) {
        return;
    }
    context->length += input_len;
    if (context->buffered != 0u) {
        size_t required = 64u - context->buffered;
        size_t take = input_len < required ? input_len : required;
        memcpy(context->buffer + context->buffered, input, take);
        context->buffered += take;
        offset = take;
        if (context->buffered < 64u) {
            return;
        }
        kc_sha256_block(context, context->buffer);
        context->buffered = 0u;
    }
    while (input_len - offset >= 64u) {
        kc_sha256_block(context, input + offset);
        offset += 64u;
    }
    if (offset < input_len) {
        context->buffered = input_len - offset;
        memcpy(context->buffer, input + offset, context->buffered);
    }
}

void kc_sha256_final(kc_sha256 *context, uint8_t out[KC_SHA256_SIZE])
{
    uint64_t bit_length;
    uint8_t tail[72];
    size_t padding;
    size_t index;

    if (context == NULL || out == NULL) {
        return;
    }
    bit_length = context->length * 8u;
    padding = context->buffered < 56u ? 56u - context->buffered
                                      : 120u - context->buffered;
    memset(tail, 0, sizeof(tail));
    tail[0] = 0x80u;
    for (index = 0u; index < 8u; index++) {
        tail[padding + index] =
            (uint8_t)(bit_length >> (56u - index * 8u));
    }
    kc_sha256_update(context, tail, padding + 8u);
    for (index = 0u; index < 8u; index++) {
        out[index * 4u] = (uint8_t)(context->state[index] >> 24u);
        out[index * 4u + 1u] = (uint8_t)(context->state[index] >> 16u);
        out[index * 4u + 2u] = (uint8_t)(context->state[index] >> 8u);
        out[index * 4u + 3u] = (uint8_t)context->state[index];
    }
    crypto_wipe(tail, sizeof(tail));
    crypto_wipe(context, sizeof(*context));
}
