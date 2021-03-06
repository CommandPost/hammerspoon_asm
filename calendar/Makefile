mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))

MODULE := $(current_dir)
PREFIX ?= ~/.hammerspoon
HS_APPLICATION ?= /Applications

OBJCFILE = ${wildcard *.m}
LUAFILE  = ${wildcard *.lua}
HEADERS  = ${wildcard *.h}

SOFILE  := $(OBJCFILE:.m=.so)
# SOFILE  := internal.so
DEBUG_CFLAGS ?= -g

# special vars for uninstall
space :=
space +=
comma := ,
ALLFILES := $(LUAFILE)
ALLFILES += $(SOFILE)

.SUFFIXES: .m .so

#CC=cc
CC=@clang
WARNINGS ?= -Weverything -Wno-objc-missing-property-synthesis -Wno-implicit-atomic-properties -Wno-direct-ivar-access -Wno-cstring-format-directive -Wno-padded -Wno-covered-switch-default -Wno-missing-prototypes -Werror-implicit-function-declaration
EXTRA_CFLAGS ?= -F$(HS_APPLICATION)/Hammerspoon.app/Contents/Frameworks

CFLAGS  += $(DEBUG_CFLAGS) -fmodules -fobjc-arc -DHS_EXTERNAL_MODULE $(WARNINGS) $(EXTRA_CFLAGS)
LDFLAGS += -dynamiclib -undefined dynamic_lookup $(EXTRA_LDFLAGS) -mmacosx-version-min=10.10

all: verify $(SOFILE)

.m.so: $(HEADERS) $(OBJCFILE)
	$(CC) $< $(CFLAGS) $(LDFLAGS) -o $@

# internal.so: $(HEADERS) $(OBJCFILE)
# 	$(CC) $(OBJCFILE) $(CFLAGS) $(LDFLAGS) -o $@

install: verify install-objc install-lua

verify: $(LUAFILE)
	@if $$(hash lua-5.3 >& /dev/null); then (luac-5.3 -p $(LUAFILE) && echo "Lua Compile Verification Passed"); else echo "Skipping Lua Compile Verification"; fi

install-objc: $(SOFILE)
	mkdir -p $(PREFIX)/hs/_asm/$(MODULE)
	install -m 0644 $(SOFILE) $(PREFIX)/hs/_asm/$(MODULE)
	cp -vpR $(OBJCFILE:.m=.so.dSYM) $(PREFIX)/hs/_asm/$(MODULE)
# 	cp -vpR $(SOFILE:.so=.so.dSYM) $(PREFIX)/hs/_asm/$(MODULE)

install-lua: $(LUAFILE)
	mkdir -p $(PREFIX)/hs/_asm/$(MODULE)
	install -m 0644 $(LUAFILE) $(PREFIX)/hs/_asm/$(MODULE)

markdown:
	hs -c "dofile(\"utils/docmaker.lua\").genMarkdown([[$(dir $(mkfile_path))]])" > README.tmp.md

markdownWithTOC:
	hs -c "dofile(\"utils/docmaker.lua\").genMarkdown([[$(dir $(mkfile_path))]], true)" > README.tmp.md

clean:
	rm -rf $(SOFILE) *.dSYM

uninstall:
	rm -v -f $(PREFIX)/hs/_asm/$(MODULE)/{$(subst $(space),$(comma),$(ALLFILES))}
	(pushd $(PREFIX)/hs/_asm/$(MODULE)/ ; rm -v -fr $(OBJCFILE:.m=.so.dSYM) ; popd)
# 	(pushd $(PREFIX)/hs/_asm/$(MODULE)/ ; rm -v -fr $(SOFILE:.so=.so.dSYM) ; popd)
	rmdir -p $(PREFIX)/hs/_asm/$(MODULE) ; exit 0

.PHONY: all clean uninstall verify install install-objc install-lua
