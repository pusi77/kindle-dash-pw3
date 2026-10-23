VERSION := pw3-v0.1.0
SRC_FILES := $(shell find src -path src/next-wakeup -prune -o \( -name '*.sh' -o -name '*.png' \) -print)
NEXT_WAKEUP_SRC_FILES := $(shell find src/next-wakeup/src -name '*.rs')
TARGET_FILES := $(SRC_FILES:src/%=dist/%)

# next-wakeup is unchanged from upstream: reuse its static armel binary instead of requiring cross/docker.
UPSTREAM_TGZ := https://github.com/pascalw/kindle-dash/releases/download/v1.0.0-beta.4/kindle-dash-v1.0.0-beta.4.tgz

# Kindle IP or hostname: make deploy KINDLE=192.168.1.50
KINDLE ?= kindle
SSH := ssh -p 2222 root@$(KINDLE)

dist: dist/next-wakeup ${TARGET_FILES}

# Laid out like the Kindle's USB drive: extract at its root (dashboard/ + documents/).
tarball: dist
	tar -czvf kindle-dash-${VERSION}.tgz --transform 's,^dist,dashboard,;s,^scriptlets,documents,' dist scriptlets

dist/%: src/%
	@echo "Copying $<"
	@mkdir -p $(@D)
	@cp "$<" "$@"

dist/next-wakeup:
	@mkdir -p dist
	curl -sSL $(UPSTREAM_TGZ) | tar -xz -C dist ./next-wakeup

# Rebuild from source instead (needs https://github.com/cross-rs/cross + docker).
build-next-wakeup: ${NEXT_WAKEUP_SRC_FILES}
	cd src/next-wakeup && cross build --release --target arm-unknown-linux-musleabi
	mkdir -p dist && cp src/next-wakeup/target/arm-unknown-linux-musleabi/release/next-wakeup dist/

# Copy to the Kindle over KOReader's SSH (port 2222). Keeps an existing local/env.sh on the device.
deploy: dist
	tar -C dist -cf - . | $(SSH) 'D=/mnt/us/dashboard; mkdir -p $$D; [ -f $$D/local/env.sh ] && cp $$D/local/env.sh /tmp/env.keep; tar -xf - -C $$D 2>/dev/null; [ -f /tmp/env.keep ] && mv /tmp/env.keep $$D/local/env.sh; echo deployed to $$D'
	tar -C scriptlets -cf - . | $(SSH) 'tar -xf - -C /mnt/us/documents 2>/dev/null'

clean:
	rm -rf dist/*

.PHONY: tarball build-next-wakeup deploy clean
