// Encode-then-decode round-trip fuzzer for libwebp.
// Loosely based on upstream tests/fuzzer/enc_dec_fuzzer.cc.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "webp/encode.h"
#include "webp/decode.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 5) return 0;

    // Use first bytes as parameters.
    int width = (data[0] % 64) + 1;
    int height = (data[1] % 64) + 1;
    float quality = (float)(data[2] % 101);
    int use_lossless = data[3] & 1;
    int method = data[4] % 7;

    size_t pixel_size = (size_t)width * height * 4;
    uint8_t *pixels = (uint8_t *)calloc(1, pixel_size);
    if (!pixels) return 0;

    // Fill pixel buffer from remaining fuzz data.
    size_t remaining = size - 5;
    if (remaining > pixel_size) remaining = pixel_size;
    memcpy(pixels, data + 5, remaining);

    WebPConfig config;
    if (!WebPConfigInit(&config)) { free(pixels); return 0; }
    config.lossless = use_lossless;
    config.quality = quality;
    config.method = method;
    if (!WebPValidateConfig(&config)) { free(pixels); return 0; }

    WebPPicture pic;
    if (!WebPPictureInit(&pic)) { free(pixels); return 0; }
    pic.width = width;
    pic.height = height;
    pic.use_argb = 1;

    if (!WebPPictureImportRGBA(&pic, pixels, width * 4)) {
        WebPPictureFree(&pic);
        free(pixels);
        return 0;
    }

    WebPMemoryWriter writer;
    WebPMemoryWriterInit(&writer);
    pic.writer = WebPMemoryWrite;
    pic.custom_ptr = &writer;

    if (WebPEncode(&config, &pic)) {
        // Decode the encoded output to test round-trip.
        int dec_w, dec_h;
        uint8_t *dec_buf = WebPDecodeRGBA(writer.mem, writer.size,
                                          &dec_w, &dec_h);
        WebPFree(dec_buf);
    }

    WebPMemoryWriterClear(&writer);
    WebPPictureFree(&pic);
    free(pixels);
    return 0;
}
