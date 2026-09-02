/*
 * boop.c — peon-boop core: fire the trackpad's Force Touch actuator on
 * demand, with NO finger/gesture requirement, via the private
 * MultitouchSupport.framework (same technique as HapticKey).
 *
 * Evolved from the haptic-poc proof of concept.
 *
 * Usage:
 *   boop                          single firm click (pattern 6, 1x)
 *   boop <pattern> [count] [gap]  e.g. boop 3 5 250
 *   boop sweep [gap_ms]           fire patterns 1..6 in sequence
 *   boop rampup   [p] [n] [s] [e] DEFAULTS: 6 12 20 200
 *                                 12 pulses, gaps grow 20ms -> 200ms
 *                                 exponentially (rapid burst easing out)
 *   boop rampdown [p] [n] [s] [e] DEFAULTS: 6 12 200 20 (mirror)
 *
 * Valid patterns on 2015+ Force Touch hardware: 1-6, 15, 16
 * (0 and 7-9 are rejected by current firmware).
 *
 * Set BOOP_QUIET=1 to suppress informational output (hook mode).
 *
 * Build:  clang -O2 -Wall -o boop boop.c -framework IOKit -framework CoreFoundation
 *
 * Private API: fine for personal tooling, will be rejected by the App
 * Store, and may break between macOS releases.
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include <stdarg.h>
#include <unistd.h>
#include <IOKit/IOKitLib.h>

#define MT_PATH "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

typedef void *mt_device_ref;
typedef void *mt_actuator_ref;

/* Signatures mirrored from HapticKey's dlopen-based bindings, with
 * macOS 26 corrections discovered in haptic-poc:
 *  - MTDeviceGetDeviceID writes through an out-pointer (does not return)
 *  - MTActuatorOpen returns kern_return_t (0 = success)
 */
static mt_device_ref (*MTDeviceCreateDefault)(void);
static void          (*MTDeviceGetDeviceID)(mt_device_ref, uint64_t *);
static void          (*MTActuatorCreateFromDeviceID)(uint64_t, mt_actuator_ref *);
static kern_return_t (*MTActuatorOpen)(mt_actuator_ref);
static int           (*MTActuatorActuate)(mt_actuator_ref, int, int, void *, void *);
static kern_return_t (*MTActuatorClose)(mt_actuator_ref);

static bool quiet(void) { return getenv("BOOP_QUIET") != NULL; }
static void msg(const char *fmt, ...)
{
    if (quiet()) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

static void die(const char *msg)
{
    fprintf(stderr, "boop: %s\n", msg);
    exit(0); /* hooks must never fail the host agent */
}

/*
 * MTActuatorCreate is NOT exported from the dyld shared cache on macOS 26,
 * but MTActuatorCreateFromDeviceID (which IS exported) calls it via:
 *
 *     mov x1, #0           ; 0xD2800001
 *     bl  MTActuatorCreate ; 0x94......
 *     mov x20, x0          ; 0xAA0003F4
 *
 * Scan the function and decode the BL target to recover its address.
 */
static mt_actuator_ref (*resolve_MTActuatorCreate(void))(io_service_t, uint64_t)
{
    uint32_t *fn = (uint32_t *)(void *)MTActuatorCreateFromDeviceID;
    for (int i = 0; i + 2 < 96; i++) {
        if (fn[i] == 0xD2800001 &&                    /* mov x1, #0  */
            (fn[i + 1] & 0xFC000000) == 0x94000000 && /* bl imm26    */
            fn[i + 2] == 0xAA0003F4) {                /* mov x20, x0 */
            int32_t imm = (int32_t)(fn[i + 1] & 0x03FFFFFF);
            imm = (imm << 6) >> 6;                    /* sign-extend 26-bit */
            uintptr_t target = (uintptr_t)&fn[i + 1] + (uintptr_t)(imm * 4);
            msg("[boop] resolved MTActuatorCreate at %p\n", (void *)target);
            return (mt_actuator_ref (*)(io_service_t, uint64_t))(void *)target;
        }
    }
    return NULL;
}

int main(int argc, char **argv)
{
    /* dlopen instead of linking, so we need no copy of the private framework */
    void *lib = dlopen(MT_PATH, RTLD_NOW);
    if (!lib) die(dlerror());

#define LOAD(var) \
    do { *(void **)&var = dlsym(lib, #var); if (!var) die("missing symbol " #var); } while (0)
    LOAD(MTDeviceCreateDefault);
    LOAD(MTDeviceGetDeviceID);
    LOAD(MTActuatorCreateFromDeviceID);
    LOAD(MTActuatorOpen);
    LOAD(MTActuatorActuate);
    LOAD(MTActuatorClose);
#undef LOAD

    mt_device_ref dev = MTDeviceCreateDefault();
    if (!dev) die("no multitouch device found (Force Touch trackpad present?)");
    uint64_t dev_id = 0;
    MTDeviceGetDeviceID(dev, &dev_id);

    mt_actuator_ref act = NULL;
    MTActuatorCreateFromDeviceID(dev_id, &act);           /* classic path (pre-Tahoe) */

    if (!act) {                                           /* macOS 26 fallback:
                                                          * IOPropertyMatch finds
                                                          * nothing and MTActuatorCreate
                                                          * is no longer exported, so
                                                          * locate the service by class
                                                          * and resolve the hidden
                                                          * MTActuatorCreate via BL
                                                          * decoding */
        mt_actuator_ref (*create)(io_service_t, uint64_t) = resolve_MTActuatorCreate();
        if (!create) die("could not resolve MTActuatorCreate");
        io_iterator_t it;
        if (IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching("AppleActuatorDevice"), &it) != KERN_SUCCESS)
            die("no AppleActuatorDevice service");
        io_service_t svc;
        while ((svc = IOIteratorNext(it))) {
            act = create(svc, 0);
            IOObjectRelease(svc);
            if (act) break;
        }
        IOObjectRelease(it);
    }

    if (!act) die("could not create actuator (Force Touch trackpad present?)");
    if (MTActuatorOpen(act) != 0) die("MTActuatorOpen failed");

    msg("[boop] device %llx actuator %p\n", (unsigned long long)dev_id, act);

    if (argc > 1 && strcmp(argv[1], "sweep") == 0) {
        int gap_ms = argc > 2 ? atoi(argv[2]) : 500;
        for (int id = 1; id <= 6; id++) {
            int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
            msg("pattern %d ... ret %d\n", id, rc);
            usleep(gap_ms * 1000);
        }
    } else if (argc > 1 && (strcmp(argv[1], "rampup") == 0 ||
                            strcmp(argv[1], "rampdown") == 0)) {
        bool up       = argv[1][4] == 'u';               /* ramp[u]p */
        int id        = argc > 2 ? atoi(argv[2]) : 6;
        int count     = argc > 3 ? atoi(argv[3]) : 12;
        int start_ms  = argc > 4 ? atoi(argv[4]) : (up ? 20  : 200);
        int end_ms    = argc > 5 ? atoi(argv[5]) : (up ? 200 : 20);
        for (int i = 0; i < count; i++) {
            int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
            double t = count > 1 ? (double)i / (count - 1) : 1.0;
            int gap = (int)(start_ms * pow((double)end_ms / start_ms, t));
            msg("pulse %2d/%d (gap %4dms) ... ret %d\n", i + 1, count, gap, rc);
            if (i < count - 1) usleep(gap * 1000);
        }
    } else {
        int id     = argc > 1 ? atoi(argv[1]) : 6;       /* default: one firm click */
        int count  = argc > 2 ? atoi(argv[2]) : 1;
        int gap_ms = argc > 3 ? atoi(argv[3]) : 250;
        for (int i = 0; i < count; i++) {
            int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
            msg("pattern %d ... ret %d\n", id, rc);
            usleep(gap_ms * 1000);
        }
    }

    MTActuatorClose(act);
    return 0;
}
