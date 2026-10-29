#include "CorkInput.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stddef.h>

// Private ABI facts only; gesture behavior and lifecycle are Cork's implementation.
// Static assertions guard the binding at build time; frames are validated before use.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTReadout;
typedef struct {
    int32_t frame; double timestamp; int32_t identifier, state, reserved1, reserved2;
    MTReadout normalized; float size; int32_t reserved3;
    float angle, majorAxis, minorAxis; MTReadout millimeters;
    int32_t reserved4[2]; float reserved5;
} MTContact;
_Static_assert(sizeof(MTContact) == 96, "Unexpected multitouch ABI size");
_Static_assert(offsetof(MTContact, normalized) == 32, "Unexpected multitouch position offset");

typedef int (*MTCallback)(void *, MTContact *, int, double, int);
static CFArrayRef (*createList)(void);
static int (*dimensions)(void *, int *, int *);
static void (*registerFrame)(void *, MTCallback);
static void (*unregisterFrame)(void *, MTCallback);
static void (*startDevice)(void *, int);
static void (*stopDevice)(void *);
static void *framework;
static CFArrayRef devices;
static void *activeDevices[16];
static int activeCount;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static CorkContactHandler receiver;
static uint64_t generation;

// All lifecycle calls are made on the main thread. The mutex protects callback delivery.
static int loadAPI(void) {
    if (framework) return createList && dimensions && registerFrame && unregisterFrame && startDevice && stopDevice;
    framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!framework) return 0;
    createList = dlsym(framework, "MTDeviceCreateList");
    dimensions = dlsym(framework, "MTDeviceGetSensorDimensions");
    registerFrame = dlsym(framework, "MTRegisterContactFrameCallback");
    unregisterFrame = dlsym(framework, "MTUnregisterContactFrameCallback");
    startDevice = dlsym(framework, "MTDeviceStart");
    stopDevice = dlsym(framework, "MTDeviceStop");
    // Keep the system framework loaded for the process lifetime, including in-flight callbacks.
    return createList && dimensions && registerFrame && unregisterFrame && startDevice && stopDevice;
}

static int compatible(void *device) {
    int rows = 0, columns = 0;
    return dimensions(device, &rows, &columns) == 0 && rows >= 10 && columns >= 10;
}

int32_t cork_trackpad_probe(void) {
    if (!loadAPI()) return -1;
    CFArrayRef list = createList(); if (!list) return 0;
    int count = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) if (compatible((void *)CFArrayGetValueAtIndex(list, i))) count++;
    CFRelease(list); return count;
}

static int frame(void *device, MTContact *touches, int count, double timestamp, int frameNumber) {
    (void)frameNumber;
    if (!isfinite(timestamp) || count < 0 || count > 16 || (count && !touches)) return 0;
    CorkContact values[16]; uint32_t live = 0;
    for (int i = 0; i < count; i++) {
        const MTContact *t = &touches[i];
        if (t->state != 3 && t->state != 4) continue;
        float x = t->normalized.position.x, y = t->normalized.position.y;
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1 || t->identifier < 0) return 0;
        values[live++] = (CorkContact){ t->identifier, x, y };
    }
    pthread_mutex_lock(&lock);
    if (receiver) receiver(generation, (uint64_t)(uintptr_t)device, values, live, timestamp);
    pthread_mutex_unlock(&lock);
    return 0;
}

void cork_trackpad_stop(void) {
    pthread_mutex_lock(&lock); receiver = NULL; generation++; pthread_mutex_unlock(&lock);
    for (int i = 0; i < activeCount; i++) { unregisterFrame(activeDevices[i], frame); stopDevice(activeDevices[i]); }
    activeCount = 0;
    if (devices) { CFRelease(devices); devices = NULL; }
}

int32_t cork_trackpad_start(CorkContactHandler handler) {
    cork_trackpad_stop();
    if (!loadAPI()) return -1;
    devices = createList(); if (!devices) return 0;
    pthread_mutex_lock(&lock); receiver = handler; pthread_mutex_unlock(&lock);
    for (CFIndex i = 0; i < CFArrayGetCount(devices) && activeCount < 16; i++) {
        void *device = (void *)CFArrayGetValueAtIndex(devices, i);
        if (!compatible(device)) continue;
        activeDevices[activeCount++] = device;
        registerFrame(device, frame); startDevice(device, 0);
    }
    return activeCount;
}

uint64_t cork_trackpad_generation(void) {
    pthread_mutex_lock(&lock); uint64_t value = generation; pthread_mutex_unlock(&lock); return value;
}
