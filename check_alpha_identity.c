/* Exhaustive check: for every float a in [0,1], does a + (1.0f - a) round to
   exactly 1.0f? This licenses the opaque-target fast path in the WP At-helpers:
   resultAlpha == 1.0f always, so the three divides are exact identities. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

int main(void) {
    uint32_t bits;
    uint64_t bad = 0, n = 0;
    float one = 1.0f;
    uint32_t oneBits;
    memcpy(&oneBits, &one, 4);
    for (bits = 0; bits <= oneBits; bits++) {   /* all floats 0.0 .. 1.0 */
        float a, u, s;
        memcpy(&a, &bits, 4);
        u = 1.0f - a;
        s = a + u;
        if (s != 1.0f) {
            if (bad < 5) printf("counterexample: a=%.9g (0x%08x) -> %.9g\n", a, bits, s);
            bad++;
        }
        n++;
    }
    printf("checked %llu floats in [0,1], violations: %llu\n",
        (unsigned long long)n, (unsigned long long)bad);
    return bad != 0;
}
