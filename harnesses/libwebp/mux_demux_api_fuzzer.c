// Mux/Demux API fuzzer for libwebp — exercises WebPDemux and WebPMux.
// Loosely based on upstream tests/fuzzer/mux_demux_api_fuzzer.cc.
#include <stdint.h>
#include <stdlib.h>
#include "webp/demux.h"
#include "webp/mux.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    WebPData webp_data = {data, size};

    // Exercise the demux API.
    WebPDemuxer *demux = WebPDemux(&webp_data);
    if (demux) {
        (void)WebPDemuxGetI(demux, WEBP_FF_CANVAS_WIDTH);
        (void)WebPDemuxGetI(demux, WEBP_FF_CANVAS_HEIGHT);
        (void)WebPDemuxGetI(demux, WEBP_FF_FRAME_COUNT);
        (void)WebPDemuxGetI(demux, WEBP_FF_LOOP_COUNT);

        WebPIterator iter;
        if (WebPDemuxGetFrame(demux, 1, &iter)) {
            int max_frames = 39;
            do {
                (void)iter.fragment;
                if (--max_frames <= 0) break;
            } while (WebPDemuxNextFrame(&iter));
            WebPDemuxReleaseIterator(&iter);
        }

        WebPChunkIterator chunk_iter;
        if (WebPDemuxGetChunk(demux, "EXIF", 1, &chunk_iter)) {
            WebPDemuxReleaseChunkIterator(&chunk_iter);
        }
        if (WebPDemuxGetChunk(demux, "ICCP", 1, &chunk_iter)) {
            WebPDemuxReleaseChunkIterator(&chunk_iter);
        }
        if (WebPDemuxGetChunk(demux, "XMP ", 1, &chunk_iter)) {
            WebPDemuxReleaseChunkIterator(&chunk_iter);
        }

        WebPDemuxDelete(demux);
    }

    // Exercise the mux API.
    WebPMux *mux = WebPMuxCreate(&webp_data, 0);
    if (mux) {
        WebPData chunk;
        WebPMuxGetChunk(mux, "ICCP", &chunk);
        WebPMuxGetChunk(mux, "EXIF", &chunk);
        WebPMuxGetChunk(mux, "XMP ", &chunk);

        WebPMuxAnimParams params;
        WebPMuxGetAnimationParams(mux, &params);

        WebPMuxDelete(mux);
    }

    return 0;
}
