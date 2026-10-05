#include "kc_internal.h"

#include <stdlib.h>

static int kc_utf8_next(const uint8_t *input,
                        size_t input_len,
                        size_t *offset,
                        uint32_t *codepoint)
{
    uint8_t first;
    uint32_t value;
    size_t length;
    size_t index;

    if (input == NULL || offset == NULL || codepoint == NULL ||
        *offset >= input_len) {
        return 0;
    }
    first = input[*offset];
    if (first < 0x80u) {
        *codepoint = first;
        *offset += 1u;
        return 1;
    }
    if (first >= 0xC2u && first <= 0xDFu) {
        value = first & 0x1Fu;
        length = 2u;
    } else if (first >= 0xE0u && first <= 0xEFu) {
        value = first & 0x0Fu;
        length = 3u;
    } else if (first >= 0xF0u && first <= 0xF4u) {
        value = first & 0x07u;
        length = 4u;
    } else {
        return 0;
    }
    if (length > input_len - *offset) {
        return 0;
    }
    for (index = 1u; index < length; index++) {
        uint8_t next = input[*offset + index];
        if ((next & 0xC0u) != 0x80u) {
            return 0;
        }
        value = (value << 6u) | (next & 0x3Fu);
    }
    if ((length == 3u && value < 0x800u) ||
        (length == 4u && value < 0x10000u) ||
        (value >= 0xD800u && value <= 0xDFFFu) || value > 0x10FFFFu) {
        return 0;
    }
    *codepoint = value;
    *offset += length;
    return 1;
}

static int kc_unicode_whitespace(uint32_t codepoint)
{
    if ((codepoint >= 0x09u && codepoint <= 0x0Du) || codepoint == 0x20u ||
        codepoint == 0x85u || codepoint == 0xA0u || codepoint == 0x1680u ||
        (codepoint >= 0x2000u && codepoint <= 0x200Au) ||
        codepoint == 0x2028u || codepoint == 0x2029u ||
        codepoint == 0x202Fu || codepoint == 0x205Fu ||
        codepoint == 0x3000u) {
        return 1;
    }
    return 0;
}

static int kc_letter_index(uint32_t codepoint, uint8_t *index)
{
    if (codepoint >= 0x410u && codepoint <= 0x42Fu) {
        codepoint += 0x20u;
    }
    if (codepoint < 0x430u || codepoint > 0x44Fu || index == NULL) {
        return 0;
    }
    *index = (uint8_t)(codepoint - 0x430u);
    return 1;
}

static void kc_write_letter(uint8_t index, uint8_t *out, size_t *offset)
{
    uint32_t codepoint = 0x430u + index;
    if (codepoint <= 0x43Fu) {
        out[*offset] = 0xD0u;
        out[*offset + 1u] = (uint8_t)(0xB0u + index);
    } else {
        out[*offset] = 0xD1u;
        out[*offset + 1u] = (uint8_t)(0x80u + index - 16u);
    }
    *offset += 2u;
}

static kc_status kc_write_symbol(uint8_t symbol,
                                 uint8_t *out,
                                 size_t out_cap,
                                 size_t *offset,
                                 size_t *run,
                                 size_t *word_len)
{
    if (*run == *word_len) {
        if (*offset >= out_cap) {
            return KC_ERR_BUFFER_TOO_SMALL;
        }
        out[*offset] = (uint8_t)' ';
        *offset += 1u;
        *run = 0u;
        *word_len = 4u + symbol % 5u;
    }
    if (out_cap - *offset < 2u) {
        return KC_ERR_BUFFER_TOO_SMALL;
    }
    kc_write_letter(symbol, out, offset);
    *run += 1u;
    return KC_OK;
}

size_t kc_alphabet_encode_bound(size_t input_len)
{
    size_t bits;
    size_t letters;
    size_t bytes;

    if (input_len > (SIZE_MAX - 4u) / 8u) {
        return 0u;
    }
    bits = input_len * 8u;
    letters = (bits + 4u) / 5u;
    if (letters > SIZE_MAX / 2u) {
        return 0u;
    }
    bytes = letters * 2u;
    if (letters != 0u && !kc_size_add(bytes, (letters - 1u) / 4u, &bytes)) {
        return 0u;
    }
    return bytes;
}

kc_status kc_alphabet_encode(const uint8_t *input,
                             size_t input_len,
                             uint8_t *out,
                             size_t out_cap,
                             size_t *out_len)
{
    uint32_t accumulator = 0u;
    unsigned int bits = 0u;
    size_t offset = 0u;
    size_t run = 0u;
    size_t word_len = 4u;
    size_t index;
    kc_status status;

    if ((input == NULL && input_len != 0u) || out_len == NULL ||
        (out == NULL && out_cap != 0u)) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    for (index = 0u; index < input_len; index++) {
        accumulator = (accumulator << 8u) | input[index];
        bits += 8u;
        while (bits >= 5u) {
            uint8_t symbol;
            bits -= 5u;
            symbol = (uint8_t)((accumulator >> bits) & 31u);
            status = kc_write_symbol(symbol, out, out_cap, &offset, &run,
                                     &word_len);
            if (status != KC_OK) {
                return status;
            }
        }
        if (bits == 0u) {
            accumulator = 0u;
        } else {
            accumulator &= (1u << bits) - 1u;
        }
    }
    if (bits != 0u) {
        uint8_t symbol = (uint8_t)((accumulator << (5u - bits)) & 31u);
        status = kc_write_symbol(symbol, out, out_cap, &offset, &run,
                                 &word_len);
        if (status != KC_OK) {
            return status;
        }
    }
    *out_len = offset;
    return KC_OK;
}

kc_status kc_alphabet_decode(const uint8_t *text,
                             size_t text_len,
                             uint8_t **out,
                             size_t *out_len)
{
    uint8_t *symbols;
    uint8_t *decoded;
    size_t symbol_count = 0u;
    size_t offset = 0u;
    size_t decoded_len;
    size_t decoded_offset = 0u;
    uint32_t accumulator = 0u;
    unsigned int bits = 0u;
    size_t index;
    size_t remainder;

    if ((text == NULL && text_len != 0u) || out == NULL || out_len == NULL) {
        return KC_ERR_INVALID_ARGUMENT;
    }
    symbols = (uint8_t *)malloc(text_len == 0u ? 1u : text_len);
    if (symbols == NULL) {
        return KC_ERR_OUT_OF_MEMORY;
    }
    while (offset < text_len) {
        uint32_t codepoint;
        uint8_t letter;
        if (!kc_utf8_next(text, text_len, &offset, &codepoint)) {
            free(symbols);
            return KC_ERR_MALFORMED;
        }
        if (kc_unicode_whitespace(codepoint)) {
            continue;
        }
        if (!kc_letter_index(codepoint, &letter)) {
            free(symbols);
            return KC_ERR_NOT_ENCRYPTED;
        }
        symbols[symbol_count++] = letter;
    }
    if (symbol_count == 0u) {
        free(symbols);
        return KC_ERR_NOT_ENCRYPTED;
    }
    remainder = symbol_count % 8u;
    if (remainder == 1u || remainder == 3u || remainder == 6u) {
        free(symbols);
        return KC_ERR_MALFORMED;
    }
    decoded_len = symbol_count * 5u / 8u;
    decoded = (uint8_t *)malloc(decoded_len == 0u ? 1u : decoded_len);
    if (decoded == NULL) {
        free(symbols);
        return KC_ERR_OUT_OF_MEMORY;
    }
    for (index = 0u; index < symbol_count; index++) {
        accumulator = (accumulator << 5u) | symbols[index];
        bits += 5u;
        if (bits >= 8u) {
            bits -= 8u;
            decoded[decoded_offset++] =
                (uint8_t)((accumulator >> bits) & 0xFFu);
        }
        if (bits == 0u) {
            accumulator = 0u;
        } else {
            accumulator &= (1u << bits) - 1u;
        }
    }
    free(symbols);
    if (bits != 0u && accumulator != 0u) {
        free(decoded);
        return KC_ERR_MALFORMED;
    }
    *out = decoded;
    *out_len = decoded_offset;
    return KC_OK;
}

int kc_utf8_valid(const uint8_t *input, size_t input_len)
{
    size_t offset = 0u;
    uint32_t codepoint;

    if (input == NULL && input_len != 0u) {
        return 0;
    }
    while (offset < input_len) {
        if (!kc_utf8_next(input, input_len, &offset, &codepoint)) {
            return 0;
        }
    }
    return 1;
}
