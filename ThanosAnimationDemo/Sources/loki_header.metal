/* Loki RNG, copyright (c) 2017 Youssef Victor; included by Telegram's DustEffect. */
#include <metal_stdlib>
using namespace metal;
#ifndef LOKI
#define LOKI
class Loki {
private:
    thread float seed;
    unsigned TausStep(const unsigned z, const int s1, const int s2, const int s3, const unsigned M);
public:
    thread Loki(const unsigned seed1, const unsigned seed2 = 1, const unsigned seed3 = 1);
    thread float rand();
};
#endif
