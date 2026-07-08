// Advanced API fuzzer for libwebp — exercises WebPDecode with decoder options.
// Loosely based on upstream tests/fuzzer/dec_fuzzer.cc.
#include <stdint.h>
#include <stdlib.h>
#include "webp/decode.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config)) return 0;

    if (size > 0) {
        config.options.bypass_filtering = data[0] & 1;
        config.options.no_fancy_upsampling = (data[0] >> 1) & 1;
        config.options.use_threads = (data[0] >> 2) & 1;
        config.options.flip = (data[0] >> 3) & 1;
        config.output.colorspace = (data[0] >> 4) % 13;
    }

    WebPDecode(data, size, &config);
    WebPFreeDecBuffer(&config.output);
    return 0;
}
