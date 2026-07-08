// Simple API fuzzer for libwebp — exercises all WebPDecode* functions.
// Loosely based on upstream tests/fuzzer/simple_api_fuzzer.cc.
#include <stdint.h>
#include <stdlib.h>
#include "webp/decode.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1) return 0;

    int w, h;
    if (!WebPGetInfo(data, size, &w, &h)) return 0;
    if ((size_t)w * h > 1024 * 1024) return 0;

    uint8_t *buf = NULL;
    switch (data[0] % 6) {
    case 0: buf = WebPDecodeRGBA(data, size, &w, &h); break;
    case 1: buf = WebPDecodeBGRA(data, size, &w, &h); break;
    case 2: buf = WebPDecodeARGB(data, size, &w, &h); break;
    case 3: buf = WebPDecodeRGB(data, size, &w, &h); break;
    case 4: buf = WebPDecodeBGR(data, size, &w, &h); break;
    case 5: {
        uint8_t *u, *v;
        int stride, uv_stride;
        buf = WebPDecodeYUV(data, size, &w, &h, &u, &v, &stride, &uv_stride);
        break;
    }
    }
    WebPFree(buf);
    return 0;
}
