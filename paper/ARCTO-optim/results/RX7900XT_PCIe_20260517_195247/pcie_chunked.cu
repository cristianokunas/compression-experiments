#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <vector>

#define CHECK(e) do{ auto _e=(e); if(_e){std::fprintf(stderr,"%s\n",hipGetErrorString(_e));std::exit(1);} }while(0)

int main(){
    const size_t chunk = 65536;
    const size_t nchunks = 1600;
    const size_t total = chunk * nchunks;  // 100 MB
    const int reps = 20;

    // Setup: device buffer, scattered pageable chunks (mimic std::vector<std::vector<char>>),
    // and a single pinned buffer of same total size.
    void* d; CHECK(hipMalloc(&d, total));
    std::vector<std::vector<char>> scattered(nchunks, std::vector<char>(chunk, 'x'));
    void* pinned_flat; CHECK(hipHostMalloc(&pinned_flat, total, hipHostMallocDefault));
    std::memset(pinned_flat, 'x', total);
    void* pageable_flat = std::malloc(total);
    std::memset(pageable_flat, 'x', total);

    hipStream_t s; CHECK(hipStreamCreate(&s));

    auto bench = [&](const char* label, auto fn){
        for(int w=0;w<3;w++) fn();
        auto t0 = std::chrono::high_resolution_clock::now();
        for(int i=0;i<reps;i++) fn();
        CHECK(hipStreamSynchronize(s));
        auto t1 = std::chrono::high_resolution_clock::now();
        double ms = std::chrono::duration<double,std::milli>(t1-t0).count()/reps;
        double gbs = (total/1e9)/(ms/1e3);
        std::printf("%-50s  %7.2f ms  %6.2f GB/s\n", label, ms, gbs);
    };

    bench("loop 1600 x 64KB scattered pageable (current bench)", [&](){
        char* dst = (char*)d;
        for(auto& c : scattered){
            CHECK(hipMemcpyAsync(dst, c.data(), c.size(), hipMemcpyHostToDevice, s));
            dst += c.size();
        }
        CHECK(hipStreamSynchronize(s));
    });

    bench("loop 1600 x 64KB scattered, pinned destination only", [&](){
        // unchanged: source pageable, just dst is the same device buf
        char* dst = (char*)d;
        for(auto& c : scattered){
            CHECK(hipMemcpyAsync(dst, c.data(), c.size(), hipMemcpyHostToDevice, s));
            dst += c.size();
        }
        CHECK(hipStreamSynchronize(s));
    });

    bench("single 100MB pageable -> device", [&](){
        CHECK(hipMemcpy(d, pageable_flat, total, hipMemcpyHostToDevice));
    });

    bench("single 100MB pinned -> device", [&](){
        CHECK(hipMemcpy(d, pinned_flat, total, hipMemcpyHostToDevice));
    });

    // The interesting one: same 1600-chunk loop but source is pinned (chunks
    // are slices into one big pinned allocation)
    bench("loop 1600 x 64KB sliced pinned -> device", [&](){
        char* dst = (char*)d;
        char* src = (char*)pinned_flat;
        for(size_t i=0;i<nchunks;i++){
            CHECK(hipMemcpyAsync(dst, src, chunk, hipMemcpyHostToDevice, s));
            dst += chunk; src += chunk;
        }
        CHECK(hipStreamSynchronize(s));
    });

    return 0;
}
