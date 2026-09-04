CC ?= clang
CFLAGS ?= -O2 -Wall
# Explicit deployment target: without one, dist/ binaries inherit the
# release machine's macOS (26.x) and refuse to load on older systems.
# 12.0 = oldest macOS we claim to support (Monterey; 2015+ Force Touch Macs).
MIN_MACOS ?= 12.0
MINFLAGS := -mmacosx-version-min=$(MIN_MACOS)
FRAMEWORKS := -framework IOKit -framework CoreFoundation

.PHONY: all clean dist install

all: bin/poke

bin/poke: src/poke.c
	@mkdir -p bin
	$(CC) $(CFLAGS) $(MINFLAGS) -o $@ $< $(FRAMEWORKS)

# Universal (arm64 + x86_64) release artifact shipped by the curl
# installer. Cross-compiles fine: MultitouchSupport is dlopen'ed at
# runtime, so only public IOKit/CoreFoundation APIs are linked.
dist/poke-darwin-universal: src/poke.c
	@mkdir -p dist
	$(CC) $(CFLAGS) $(MINFLAGS) -arch arm64 -arch x86_64 -o $@ $< $(FRAMEWORKS)

dist: dist/poke-darwin-universal

print-min:
	@echo $(MIN_MACOS)

clean:
	rm -rf bin
