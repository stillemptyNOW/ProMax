CC ?= cc
BUILD = build
CPPFLAGS = -Iinclude -Isrc -Ithird_party/monocypher -DKC_BUILDING
CFLAGS = -std=c99 -O2 -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion -Wstrict-prototypes
CORE_SOURCES = $(filter-out src/kc_all.c,$(wildcard src/*.c))
CORE_HEADERS = $(wildcard src/*.h) include/promax_crypto.h
MONOCYPHER_SOURCE = third_party/monocypher/monocypher.c
MONOCYPHER_OBJECT = $(BUILD)/monocypher.o
TEST_SOURCES = tests/test_core.c tests/test_v2.c
TEST = $(BUILD)/test_core
FUZZ = $(BUILD)/fuzz_decode
VECTORS = $(BUILD)/gen_vectors
UNAME_S = $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
SHARED = $(BUILD)/libpromax_crypto.dylib
SHARED_FLAGS = -dynamiclib -Wl,-dead_strip -Wl,-install_name,@rpath/libpromax_crypto.dylib
else
SHARED = $(BUILD)/libpromax_crypto.so
SHARED_FLAGS = -shared -Wl,--gc-sections
endif

.DEFAULT_GOAL := test

.PHONY: test asan shared fuzz vectors aggregate android clean

$(BUILD):
	mkdir -p $(BUILD)

$(MONOCYPHER_OBJECT): $(MONOCYPHER_SOURCE) third_party/monocypher/monocypher.h | $(BUILD)
	$(CC) $(CPPFLAGS) $(filter-out -Wconversion,$(CFLAGS)) -fPIC -fvisibility=hidden -ffunction-sections -fdata-sections -c $(MONOCYPHER_SOURCE) -o $(MONOCYPHER_OBJECT)

$(TEST): $(CORE_SOURCES) $(MONOCYPHER_OBJECT) $(TEST_SOURCES) $(CORE_HEADERS) | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(CORE_SOURCES) $(MONOCYPHER_OBJECT) $(TEST_SOURCES) -o $(TEST)

test: $(TEST) aggregate
	$(TEST)

aggregate: | $(BUILD)
	@for f in $(notdir $(CORE_SOURCES)); do \
		grep -q "\"$$f\"" src/kc_all.c || { echo "kc_all.c не включает $$f"; exit 1; }; \
	done
	@grep -c '#include "' src/kc_all.c | grep -qx "$(words $(CORE_SOURCES))" || \
		{ echo "kc_all.c включает файлы, которых нет в src/"; exit 1; }
	$(CC) $(CPPFLAGS) $(CFLAGS) -fsyntax-only src/kc_all.c $(TEST_SOURCES) \
		tests/fuzz_decode.c tools/gen_vectors.c

$(SHARED): $(CORE_SOURCES) $(MONOCYPHER_OBJECT) $(CORE_HEADERS) | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) -fPIC -fvisibility=hidden -ffunction-sections -fdata-sections $(SHARED_FLAGS) $(CORE_SOURCES) $(MONOCYPHER_OBJECT) -o $(SHARED)

shared: $(SHARED)

$(VECTORS): $(CORE_SOURCES) $(MONOCYPHER_OBJECT) tools/gen_vectors.c $(CORE_HEADERS) | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(CORE_SOURCES) $(MONOCYPHER_OBJECT) tools/gen_vectors.c -o $(VECTORS)

vectors: $(VECTORS)
	$(VECTORS) > tests/vectors/v3.json

ASAN_CFLAGS = -std=c99 -O1 -g -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion -Wstrict-prototypes -fsanitize=address,undefined -fno-omit-frame-pointer
FUZZ_CFLAGS = -std=c99 -O1 -g -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion -Wstrict-prototypes -fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer

asan:
	$(MAKE) BUILD=build/asan CFLAGS="$(ASAN_CFLAGS)" test

$(FUZZ): $(CORE_SOURCES) $(MONOCYPHER_OBJECT) tests/fuzz_decode.c $(CORE_HEADERS) | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(CORE_SOURCES) $(MONOCYPHER_OBJECT) tests/fuzz_decode.c -o $(FUZZ)

fuzz: $(VECTORS)
	$(MAKE) BUILD=build/fuzz CC=clang CFLAGS="$(FUZZ_CFLAGS)" build/fuzz/fuzz_decode
	mkdir -p build/fuzz/corpus
	$(VECTORS) --seed-corpus build/fuzz/corpus
	build/fuzz/fuzz_decode -dict=tests/fuzz.dict -max_total_time=$(or $(FUZZ_SECONDS),60) -max_len=4096 build/fuzz/corpus

android:
	tools/build-android.sh

clean:
	rm -rf $(BUILD)
