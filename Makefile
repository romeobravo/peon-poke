CC ?= clang
CFLAGS ?= -O2 -Wall
FRAMEWORKS := -framework IOKit -framework CoreFoundation

.PHONY: all clean install

all: bin/poke

bin/poke: src/poke.c
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $< $(FRAMEWORKS)

install: all

clean:
	rm -rf bin
