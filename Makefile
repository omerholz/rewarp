# Building, testing and packaging Rewarp. Run `make` to list the commands.
#
# The work stays in scripts/, where it reads as plain shell. This file only gives
# it one front door, and sticks to the GNU Make 3.81 that ships with macOS.

.DEFAULT_GOAL := help
# SwiftPM holds a lock on .build, so its steps can't overlap anyway.
.NOTPARALLEL:

VERSION     := $(shell scripts/version.sh)
APP         := dist/Rewarp.app
ZIP         := dist/Rewarp-$(VERSION).zip
DMG         := dist/Rewarp-$(VERSION).dmg
DMG_ROOT    := .build/dmg
INSTALL_DIR ?= /Applications
MB          ?= 512
KIND        ?= scroll

.PHONY: help deps build release test e2e check bench icons app run zip dmg package install clean distclean

help: ## List these commands
	@echo "Rewarp $(VERSION)"
	@awk 'BEGIN { FS = ":.*## " } /^[a-z0-9]+:.*## / { printf "  make %-10s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

deps: ## Build the pinned libghostty-vt (needs Zig, skipped when up to date)
	@scripts/build-ghostty-vt.sh

build: deps ## Build the debug binary
	@swift build --product Rewarp

release: deps ## Build the optimized binary
	@swift build -c release --product Rewarp

test: deps ## Run the unit tests (FILTER=name narrows them)
	@scripts/test.sh $(if $(FILTER),--filter "$(FILTER)")

e2e: build ## Run the end-to-end tests on the real app (FILTER=name narrows them)
	@python3 tests-e2e/run.py $(FILTER)

check: test e2e ## Run every test

bench: deps ## Compare throughput with Ghostty (MB=512, KIND=scroll or repaint)
	@scripts/bench.sh $(MB) $(KIND)

icons: ## Regenerate the macOS app icon from resources/icons/Rewarp.png
	@scripts/build-icons.sh

app: ## Assemble dist/Rewarp.app from a release build
	@scripts/bundle.sh

run: app ## Build the app and open it
	@open $(APP)

zip: app ## Package the app as a zip in dist/
	@rm -f $(ZIP)
	@ditto -c -k --keepParent $(APP) $(ZIP)
	@echo "built $(ZIP)"

dmg: app ## Package the app as a disk image in dist/
	@rm -rf $(DMG_ROOT) $(DMG)
	@mkdir -p $(DMG_ROOT)
	@ditto $(APP) $(DMG_ROOT)/Rewarp.app
	@ln -s /Applications $(DMG_ROOT)/Applications
	@hdiutil create -quiet -volname "Rewarp $(VERSION)" -srcfolder $(DMG_ROOT) -format UDZO $(DMG)
	@rm -rf $(DMG_ROOT)
	@echo "built $(DMG)"

package: zip dmg ## Build both the zip and the disk image

install: app ## Copy the app to /Applications (INSTALL_DIR=path changes that)
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/Rewarp.app"
	@ditto $(APP) "$(INSTALL_DIR)/Rewarp.app"
	@echo "installed $(INSTALL_DIR)/Rewarp.app"

clean: ## Remove build output, keeping the slow libghostty-vt build
	@rm -rf .build dist

distclean: clean ## Remove everything that can be rebuilt, libghostty-vt included
	@rm -rf vendor Sources/CGhosttyVT/include/ghostty
