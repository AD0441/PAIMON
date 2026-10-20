#include "AudioRing.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#define SLOTS 64
#define FRAMES 8192
typedef struct { float samples[FRAMES]; uint32_t count; uint64_t time; } Slot;
struct LAIRing { Slot slots[SLOTS]; _Atomic uint64_t read; _Atomic uint64_t write; _Atomic uint64_t dropped; };
LAIRing *lai_ring_create(void) { return calloc(1, sizeof(LAIRing)); }
void lai_ring_destroy(LAIRing *r) { free(r); }
uint32_t lai_ring_max_frames(void) { return FRAMES; }
uint64_t lai_ring_dropped(LAIRing *r) { return atomic_load_explicit(&r->dropped, memory_order_relaxed); }
void lai_ring_clear(LAIRing *r) { atomic_store(&r->read, atomic_load(&r->write)); }
void lai_ring_push(LAIRing *r, const AudioBufferList *b, const AudioStreamBasicDescription *f, uint64_t time) {
    if (!r || !b || !b->mNumberBuffers || !f->mBytesPerFrame) return;
    uint64_t w = atomic_load_explicit(&r->write, memory_order_relaxed);
    if (w - atomic_load_explicit(&r->read, memory_order_acquire) >= SLOTS) { atomic_fetch_add(&r->dropped, 1); return; }
    uint32_t n = b->mBuffers[0].mDataByteSize / f->mBytesPerFrame;
    if (n > FRAMES) { atomic_fetch_add(&r->dropped, 1); return; }
    bool fp = (f->mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    bool signedInt = (f->mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0;
    if ((!fp || f->mBitsPerChannel != 32) && (!signedInt || f->mBitsPerChannel != 16)) { atomic_fetch_add(&r->dropped, 1); return; }
    Slot *s = &r->slots[w % SLOTS];
    uint32_t channels = 0;
    memset(s->samples, 0, n * sizeof(float));
    for (uint32_t j=0; j<b->mNumberBuffers; j++) {
        const AudioBuffer *ab = &b->mBuffers[j];
        if (!ab->mData) continue;
        uint32_t c = ab->mNumberChannels;
        if (ab->mDataByteSize < n*c*(f->mBitsPerChannel/8)) continue;
        channels += c;
        for (uint32_t i=0; i<n; i++) for (uint32_t k=0; k<c; k++) {
            s->samples[i] += fp ? ((const float *)ab->mData)[i*c+k] : ((const int16_t *)ab->mData)[i*c+k]/32768.0f;
        }
    }
    if (!channels) return;
    for (uint32_t i=0; i<n; i++) s->samples[i] /= channels;
    s->count=n; s->time=time;
    atomic_store_explicit(&r->write, w+1, memory_order_release);
}
uint32_t lai_ring_pop(LAIRing *r, float *out, uint32_t capacity, uint64_t *time) {
    uint64_t rd=atomic_load_explicit(&r->read, memory_order_relaxed);
    if (rd == atomic_load_explicit(&r->write, memory_order_acquire)) return 0;
    Slot *s=&r->slots[rd % SLOTS];
    if (capacity < s->count) return 0;
    memcpy(out,s->samples,s->count*sizeof(float)); *time=s->time;
    uint32_t n=s->count;
    atomic_store_explicit(&r->read,rd+1,memory_order_release); return n;
}
