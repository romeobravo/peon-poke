/*
 * boop.c — peon-boop core: fire the trackpad's Force Touch actuator on
 * demand, with NO finger/gesture requirement, via the private
 * MultitouchSupport.framework (same technique as HapticKey).
 *
 * Usage:
 *   boop                      default pattern: chirp
 *   boop <name>               named pattern (see table below)
 *   boop 60,120,40,80         explicit gap sequence, in ms
 *   boop [60, 120, 40, 80]    brackets/spaces also accepted
 *
 * A gap sequence fires one pulse per gap plus a final pulse:
 *   "50,80,50" -> pulse-50ms-pulse-80ms-pulse-50ms-pulse
 *
 * Named patterns:
 *   boop      single firm click
 *   chirp     20,20,20,200,20,20,20,200,20,20,20     (default)
 *   skrrt     20,20,20,20,20,20,200,20,20,20,20,20,20
 *   callme    60,120,40,80,40,120,60,300,60,120,60
 *   rimshot   50,80,50,120,150
 *   heart     200,700,200,700,200,700
 *   slowdown  exponential ramp, 12 pulses, 200ms -> 20ms (the old rampdown)
 *
 * Click intensity (actuation id) defaults to 6; override with BOOP_PATTERN
 * (valid ids: 1-6, 15, 16).
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

/* ------------------------------------------------------------------ */
/* Pattern engine: gap sequences + a couple of generated specials      */

struct named_pattern {
    const char *name;
    const char *gaps;   /* NULL => generated below */
};

static const struct named_pattern NAMED[] = {
    { "boop",    NULL },
    { "chirp",   "20,20,20,200,20,20,20,200,20,20,20" },
    { "skrrt",   "20,20,20,20,20,20,200,20,20,20,20,20,20" },
    { "callme",  "60,120,40,80,40,120,60,300,60,120,60" },
    { "rimshot", "50,80,50,120,150" },
    { "heart",   "200,700,200,700,200,700" },
    { "slowdown", NULL },
};

/* fire one pulse per gap, plus a final pulse */
static void play_sequence(mt_actuator_ref act, int id, const char *spec)
{
    char *copy = strdup(spec);
    if (!copy) return;
    int n = 1;
    for (char *tok = strtok(copy, ","); tok; tok = strtok(NULL, ",")) {
        int gap = atoi(tok);
        int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
        msg("pulse %2d (gap %4dms) ... ret %d\n", n++, gap, rc);
        usleep(gap * 1000);
    }
    int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
    msg("pulse %2d (final) ... ret %d\n", n, rc);
    free(copy);
}

/* exponential ramp: 12 pulses, gaps 200ms -> 20ms (the classic slowdown) */
static void play_slowdown(mt_actuator_ref act, int id)
{
    int count = 12, start = 200, end = 20;
    for (int i = 0; i < count; i++) {
        double t = count > 1 ? (double)i / (count - 1) : 1.0;
        int gap = (int)(start * pow((double)end / start, t));
        int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
        msg("pulse %2d/%d (gap %4dms) ... ret %d\n", i + 1, count, gap, rc);
        if (i < count - 1) usleep(gap * 1000);
    }
}

static void usage(void)
{
    fprintf(stderr,
        "usage: boop [name | g1,g2,...,gN]\n"
        "  names: boop chirp skrrt callme rimshot heart slowdown\n"
        "  gaps:  milliseconds between pulses, e.g. boop 60,120,40\n");
}

/* strip '[' ']' and whitespace in place */
static void clean_spec(char *s)
{
    char *w = s;
    for (char *r = s; *r; r++)
        if (*r != '[' && *r != ']' && *r != ' ')
            *w++ = *r;
    *w = '\0';
}

/* ------------------------------------------------------------------ */

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

    int id = 6;
    if (getenv("BOOP_PATTERN")) {
        int v = atoi(getenv("BOOP_PATTERN"));
        if (v >= 1) id = v;
    }

    /* resolve the pattern argument (default: chirp) */
    char spec[512];
    snprintf(spec, sizeof spec, "%s", argc > 1 ? argv[1] : "chirp");
    clean_spec(spec);

    if (strcmp(spec, "boop") == 0) {
        int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
        msg("pulse (single) ... ret %d\n", rc);
    } else if (strcmp(spec, "slowdown") == 0) {
        play_slowdown(act, id);
    } else if (strchr(spec, ',')) {
        play_sequence(act, id, spec);
    } else {
        const struct named_pattern *np = NULL;
        for (size_t i = 0; i < sizeof NAMED / sizeof NAMED[0]; i++)
            if (strcmp(spec, NAMED[i].name) == 0) { np = &NAMED[i]; break; }
        if (!np) { usage(); die("unknown pattern"); }
        play_sequence(act, id, np->gaps);
    }

    MTActuatorClose(act);
    return 0;
}
