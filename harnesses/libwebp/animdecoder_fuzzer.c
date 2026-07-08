// Animated WebP decoder fuzzer — exercises the WebPAnimDecoder API.
// Loosely based on upstream tests/fuzzer/animdecoder_fuzzer.cc.
#include <stdint.h>
#include <stdlib.h>
#include "webp/decode.h"
#include "webp/demux.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    WebPData webp_data = {data, size};
    WebPAnimDecoderOptions opts;
    if (!WebPAnimDecoderOptionsInit(&opts)) return 0;
    opts.color_mode = MODE_RGBA;

    WebPAnimDecoder *dec = WebPAnimDecoderNew(&webp_data, &opts);
    if (dec) {
        WebPAnimInfo info;
        if (WebPAnimDecoderGetInfo(dec, &info)) {
            if ((uint64_t)info.canvas_width * info.canvas_height <= 1024 * 1024) {
                int max_frames = 39;
                while (WebPAnimDecoderHasMoreFrames(dec) && max_frames-- > 0) {
                    uint8_t *buf;
                    int timestamp;
                    if (!WebPAnimDecoderGetNext(dec, &buf, &timestamp)) break;
                }
            }
        }
        WebPAnimDecoderDelete(dec);
    }
    return 0;
}
