#ifndef KC_CODEC_H
#define KC_CODEC_H

#include <stddef.h>
#include <stdint.h>

static inline void kc_store_u32(uint8_t *out, uint32_t value)
{
    out[0] = (uint8_t)(value >> 24u);
    out[1] = (uint8_t)(value >> 16u);
    out[2] = (uint8_t)(value >> 8u);
    out[3] = (uint8_t)value;
}

static inline uint32_t kc_load_u32(const uint8_t *in)
{
    return ((uint32_t)in[0] << 24u) | ((uint32_t)in[1] << 16u) |
           ((uint32_t)in[2] << 8u) | (uint32_t)in[3];
}

static inline void kc_store_u64(uint8_t *out, uint64_t value)
{
    kc_store_u32(out, (uint32_t)(value >> 32u));
    kc_store_u32(out + 4, (uint32_t)value);
}

static inline uint64_t kc_load_u64(const uint8_t *in)
{
    return ((uint64_t)kc_load_u32(in) << 32u) | (uint64_t)kc_load_u32(in + 4);
}

static inline void kc_store_i64(uint8_t *out, int64_t value)
{
    kc_store_u64(out, (uint64_t)value);
}

static inline int64_t kc_load_i64(const uint8_t *in)
{
    return (int64_t)kc_load_u64(in);
}

#endif
