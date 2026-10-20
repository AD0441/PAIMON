#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>
typedef struct LAIRing LAIRing;
// Single producer / single consumer. All storage is allocated before audio starts.
LAIRing *lai_ring_create(void);
void lai_ring_destroy(LAIRing *ring);
void lai_ring_push(LAIRing *ring, const AudioBufferList *buffers, const AudioStreamBasicDescription *format, uint64_t hostTime);
uint32_t lai_ring_pop(LAIRing *ring, float *output, uint32_t capacity, uint64_t *hostTime);
uint64_t lai_ring_dropped(LAIRing *ring);
void lai_ring_clear(LAIRing *ring); // Consumer only, producer must be stopped.
uint32_t lai_ring_max_frames(void);
