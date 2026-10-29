#pragma once
#include <stdint.h>

typedef struct { int32_t identifier; double x; double y; } CorkContact;
typedef void (*CorkContactHandler)(uint64_t generation, uint64_t device, const CorkContact *contacts, uint32_t count, double timestamp);

// Runtime-loaded private Apple API. No contacts are read by the capability probe.
int32_t cork_trackpad_probe(void);
int32_t cork_trackpad_start(CorkContactHandler handler);
void cork_trackpad_stop(void);
uint64_t cork_trackpad_generation(void);
