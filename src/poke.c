/*
 * poke.c — peon-poke core: fire the trackpad's Force Touch actuator on
 * demand, with NO finger/gesture requirement, via the private
 * MultitouchSupport.framework (same technique as HapticKey).
 *
 * Usage:
 *   poke                      default pattern: fortune
 *   poke <name>               named pattern (see table below)
 *   poke 60,120,40,80         explicit gap sequence, in ms
 *   poke [60, 120, 40, 80]    brackets/spaces also accepted
 *
 * A gap sequence fires one pulse per gap plus a final pulse:
 *   "50,80,50" -> pulse-50ms-pulse-80ms-pulse-50ms-pulse
 * Each gap is clamped to 0-10000 ms: usleep takes an unsigned count, so
 * an unclamped negative gap used to wrap to ~71 minutes.
 *
 * Named patterns:
 *   boop      single firm click
 *   fortune   50,80,140,240,400 (fortune wheel: fast ticks slowing to a stop)
 *                                             (default)
 *   chirp     20,20,20,200,20,20,20,200,20,20,20
 *   skrrt     20,20,20,20,20,20,200,20,20,20,20,20,20
 *   callme    60,120,40,80,40,120,60,300,60,120,60
 *   rimshot   50,80,50,120,150
 *   heartbeat 200,700,200,700,200,700
 *   rampup    200,162,132,107,87,70,57,46,37,30,25,20 (precomputed exp ramp,
 *             speeds up: slow ... rapid)
 *
 * Click intensity (actuation id) defaults to 6; override with POKE_PATTERN
 * (valid ids: 1-6; anything else falls back to 6).
 *
 * Set POKE_QUIET=1 to suppress informational output (hook mode).
 *
 * If the MacBook lid is closed (clamshell mode) the built-in trackpad's
 * actuator is asleep: poke says so on stderr and exits 0. A crash guard
 * catches SIGBUS/SIGSEGV/SIGILL from the private framework (revoked
 * IOKit mappings, e.g. display asleep) so the exit-0 invariant holds.
 * External Magic Trackpads expose no actuator and cannot be poked.
 *
 * Build:  clang -O2 -Wall -o poke poke.c -framework IOKit -framework CoreFoundation
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
#include <stdarg.h>
#include <unistd.h>
#include <signal.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

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

static bool quiet(void) { return getenv("POKE_QUIET") != NULL; }
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
    fprintf(stderr, "poke: %s\n", msg);
    exit(0); /* hooks must never fail the host agent */
}

/*
 * Crash guard. With the lid closed (or the display asleep) the internal
 * trackpad's actuator service can be suspended/terminating, and
 * MultitouchSupport dies with SIGBUS inside MTActuatorCreate/Open while
 * touching revoked IOKit mappings. Catch the fault, say something human,
 * and keep the exit-0 invariant. write() only — fprintf is not
 * async-signal-safe. Hook mode never sees this: poke.sh redirects stderr.
 */
static void crash_guard(int sig)
{
    static const char note[] =
        "poke: can't reach the trackpad actuator (lid closed? trackpad "
        "asleep? Magic Trackpads unsupported) — nothing fired\n";
    (void)sig;
    (void)!write(STDERR_FILENO, note, sizeof note - 1);
    _exit(0);
}

/* True when the MacBook lid is closed (clamshell). The internal trackpad
 * is asleep then; poking would at best fail, at worst crash (above).
 * Desktop Macs publish no AppleClamshellState -> false. */
static bool lid_closed(void)
{
    io_service_t root = IOServiceGetMatchingService(kIOMainPortDefault,
                                                    IOServiceMatching("IOPMrootDomain"));
    if (!root) return false;
    CFTypeRef v = IORegistryEntryCreateCFProperty(root, CFSTR("AppleClamshellState"),
                                                  kCFAllocatorDefault, 0);
    IOObjectRelease(root);
    if (!v || CFGetTypeID(v) != CFBooleanGetTypeID()) {
        if (v) CFRelease(v);
        return false;
    }
    bool closed = CFBooleanGetValue(v);
    CFRelease(v);
    return closed;
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
            msg("[poke] resolved MTActuatorCreate at %p\n", (void *)target);
            return (mt_actuator_ref (*)(io_service_t, uint64_t))(void *)target;
        }
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Pattern engine: everything is a literal gap sequence                */

struct named_pattern {
    const char *name;
    const char *gaps;   /* NULL => single pulse */
};

static const struct named_pattern NAMED[] = {
    { "boop",      NULL },
    { "fortune",   "50,80,140,240,400" },
    { "chirp",     "20,20,20,200,20,20,20,200,20,20,20" },
    { "skrrt",     "20,20,20,20,20,20,200,20,20,20,20,20,20" },
    { "callme",    "60,120,40,80,40,120,60,300,60,120,60" },
    { "rimshot",   "50,80,50,120,150" },
    { "heartbeat", "200,700,200,700,200,700" },
    { "rampup",    "200,162,132,107,87,70,57,46,37,30,25,20" },
};

/* per-gap ceiling in ms — keeps a bad config value from parking a
 * background process for the better part of an hour */
#define GAP_MAX_MS 10000

/* fire one pulse per gap, plus a final pulse; NULL spec = single pulse
 * (also protects NAMED entries with gaps == NULL if the boop special
 * case in main() ever moves) */
static void play_sequence(mt_actuator_ref act, int id, const char *spec)
{
    if (!spec) {
        int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
        msg("pulse (single) ... ret %d\n", rc);
        return;
    }
    char *copy = strdup(spec);
    if (!copy) return;
    int n = 1;
    for (char *tok = strtok(copy, ","); tok; tok = strtok(NULL, ",")) {
        int gap = atoi(tok);
        if (gap < 0) gap = 0;
        if (gap > GAP_MAX_MS) gap = GAP_MAX_MS;
        int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
        msg("pulse %2d (gap %4dms) ... ret %d\n", n++, gap, rc);
        usleep(gap * 1000);
    }
    int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
    msg("pulse %2d (final) ... ret %d\n", n, rc);
    free(copy);
}

static void usage(void)
{
    fprintf(stderr,
        "usage: poke [name | g1,g2,...,gN]\n"
        "  names: boop fortune chirp skrrt callme rimshot heartbeat rampup\n"
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
    /* belt and suspenders before anything touches the private framework */
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = crash_guard;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);

    if (lid_closed())
        die("lid closed — the built-in trackpad is asleep and Magic "
            "Trackpads have no actuator, nothing fired");

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

    msg("[poke] device %llx actuator %p\n", (unsigned long long)dev_id, act);

    int id = 6;
    if (getenv("POKE_PATTERN")) {
        int v = atoi(getenv("POKE_PATTERN"));
        if (v >= 1 && v <= 6) id = v;
    }

    /* resolve the pattern argument (default: fortune) */
    char spec[512];
    snprintf(spec, sizeof spec, "%s", argc > 1 ? argv[1] : "fortune");
    clean_spec(spec);

    if (strcmp(spec, "boop") == 0) {
        int rc = MTActuatorActuate(act, id, 0, NULL, NULL);
        msg("pulse (single) ... ret %d\n", rc);
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
