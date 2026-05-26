#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <vector>

#define CHECK(e) do{ auto _e=(e); if(_e){std::fprintf(stderr,"%s\n",hipGetErrorString(_e));std::exit(1);} }while(0)

double bench_h2d(void* h, void* d, size_t sz, int reps){
    auto t0=std::chrono::high_resolution_clock::now();
    for(int i=0;i<reps;i++) CHECK(hipMemcpy(d,h,sz,hipMemcpyHostToDevice));
    CHECK(hipDeviceSynchronize());
    auto t1=std::chrono::high_resolution_clock::now();
    double ms=std::chrono::duration<double,std::milli>(t1-t0).count()/reps;
    return (sz/1e9)/(ms/1e3);
}
double bench_d2h(void* h, void* d, size_t sz, int reps){
    auto t0=std::chrono::high_resolution_clock::now();
    for(int i=0;i<reps;i++) CHECK(hipMemcpy(h,d,sz,hipMemcpyDeviceToHost));
    CHECK(hipDeviceSynchronize());
    auto t1=std::chrono::high_resolution_clock::now();
    double ms=std::chrono::duration<double,std::milli>(t1-t0).count()/reps;
    return (sz/1e9)/(ms/1e3);
}

int main(int argc, char** argv){
    size_t sz = (argc>1)? std::strtoull(argv[1],nullptr,10) : 100ull<<20;
    int reps = 20;
    void* d; CHECK(hipMalloc(&d, sz));
    std::vector<char> pageable(sz, 'x');
    void* pinned; CHECK(hipHostMalloc(&pinned, sz, hipHostMallocDefault));
    std::memset(pinned, 'x', sz);

    // warmup
    bench_h2d(pageable.data(), d, sz, 3);
    bench_h2d(pinned, d, sz, 3);

    std::printf("%-30s %10.2f GB/s\n", "H2D pageable",      bench_h2d(pageable.data(), d, sz, reps));
    std::printf("%-30s %10.2f GB/s\n", "H2D pinned (Default)", bench_h2d(pinned, d, sz, reps));
    std::printf("%-30s %10.2f GB/s\n", "D2H pageable",      bench_d2h(pageable.data(), d, sz, reps));
    std::printf("%-30s %10.2f GB/s\n", "D2H pinned (Default)", bench_d2h(pinned, d, sz, reps));
    return 0;
}
