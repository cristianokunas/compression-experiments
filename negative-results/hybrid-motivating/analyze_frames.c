/* Per-frame compressibility analysis of a fletcher .rsf@ raw dump.
 * For each frame (n1*n2*n3 floats): zero fraction, LZ4 ratio (64 KiB chunks,
 * mirroring the ARCTO chunked pipeline), ZFP fixed-accuracy ratio at two
 * tolerances. CSV on stdout. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <lz4.h>
#include "zfp.h"

static size_t lz4_chunked(const char* src, size_t n, char* dst, size_t chunk) {
    size_t total = 0;
    for (size_t off = 0; off < n; off += chunk) {
        int in = (int)((n - off) < chunk ? (n - off) : chunk);
        int out = LZ4_compress_default(src + off, dst, in, LZ4_compressBound(in));
        if (out <= 0) { fprintf(stderr, "lz4 failure at %zu\n", off); exit(1); }
        total += (size_t)out;
    }
    return total;
}

static size_t zfp_acc(float* data, size_t n1, size_t n2, size_t n3, double tol,
                      void* buf, size_t cap) {
    zfp_field* field = zfp_field_3d(data, zfp_type_float, n1, n2, n3);
    zfp_stream* zfp = zfp_stream_open(NULL);
    zfp_stream_set_accuracy(zfp, tol);
    size_t need = zfp_stream_maximum_size(zfp, field);
    if (need > cap) { fprintf(stderr, "zfp buffer too small\n"); exit(1); }
    bitstream* bs = stream_open(buf, cap);
    zfp_stream_set_bit_stream(zfp, bs);
    zfp_stream_rewind(zfp);
    size_t sz = zfp_compress(zfp, field);
    if (!sz) { fprintf(stderr, "zfp_compress failed\n"); exit(1); }
    stream_close(bs);
    zfp_stream_close(zfp);
    zfp_field_free(field);
    return sz;
}

int main(int argc, char** argv) {
    if (argc != 5) { fprintf(stderr, "usage: %s file.rsf@ n1 n2 n3\n", argv[0]); return 1; }
    size_t n1 = atol(argv[2]), n2 = atol(argv[3]), n3 = atol(argv[4]);
    size_t vol = n1 * n2 * n3, bytes = vol * sizeof(float);
    FILE* f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 1; }

    float* frame = malloc(bytes);
    size_t cap = bytes * 2 + (1 << 20);
    char* cbuf = malloc(cap);
    if (!frame || !cbuf) { fprintf(stderr, "oom\n"); return 1; }

    printf("frame,zero_frac,lz4_ratio,zfp_acc1e13_ratio,zfp_acc1e6_ratio\n");
    for (int fi = 0; fread(frame, 1, bytes, f) == bytes; ++fi) {
        size_t zeros = 0;
        for (size_t i = 0; i < vol; ++i) zeros += (frame[i] == 0.0f);
        size_t lz4_sz = lz4_chunked((const char*)frame, bytes, cbuf, 64 * 1024);
        size_t z13 = zfp_acc(frame, n1, n2, n3, 1e-13, cbuf, cap);
        size_t z6  = zfp_acc(frame, n1, n2, n3, 1e-6,  cbuf, cap);
        printf("%d,%.6f,%.4f,%.4f,%.4f\n", fi, (double)zeros / vol,
               (double)bytes / lz4_sz, (double)bytes / z13, (double)bytes / z6);
        fflush(stdout);
    }
    fclose(f); free(frame); free(cbuf);
    return 0;
}
