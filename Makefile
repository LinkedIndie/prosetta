EXEC     := Prosetta
CONFIG   := debug
APPNAME  := Prosetta.app

## Build products and the assembled bundle live OUTSIDE the source tree, same reasoning as Parla's
## own Makefile: a cloud-synced folder (this repo lives under OneDrive) mutates files inside a
## build directory while the compiler has them open, and re-stamps Finder metadata on the .app
## faster than it can be stripped before codesign, which codesign then refuses outright.
## ~/Library/Caches is never synced, which sidesteps both.
STAGE    := $(HOME)/Library/Caches/ProsettaBuild
SCRATCH  := $(STAGE)/scratch
BUILD    := $(SCRATCH)/$(CONFIG)/$(EXEC)
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents

INSTALL_DIR := $(HOME)/Applications

BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
MARKETING_VERSION := 0.1.0

## The SDK is pinned for the same reason Parla's is — see that project's Makefile for the full
## story of why a Command Line Tools SDK update once broke SwiftUI macro expansion outright.
SDKROOT_PICK := $(shell ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)
ifeq ($(strip $(SDKROOT_PICK)),)
SDKROOT_PICK := $(shell xcrun --show-sdk-path 2>/dev/null)
endif

## TCC ties the Microphone grant to the code signature, so a signature that changes on every
## build (ad-hoc) forces a re-grant on every rebuild. Same fallback chain as Parla's Makefile:
## a paid Developer ID cert, then a self-signed local identity, then ad-hoc as a last resort.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Prosetta Local" | head -1 | sed -E 's/.*"(.*)".*/\1/')
endif
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)".*/\1/')
endif
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

DMG_NAME := Prosetta-$(MARKETING_VERSION).dmg
DMG_DEST := $(HOME)/Desktop/$(DMG_NAME)
DMG_STAGE := $(STAGE)/dmg-staging

.PHONY: all build app run install dmg clean

all: app

build:
	@echo "building against $(notdir $(SDKROOT_PICK))"
	SDKROOT="$(SDKROOT_PICK)" swift build -c $(CONFIG) --scratch-path "$(SCRATCH)"

ICON_SRC  := Resources/AppIcon.png
ICON_ICNS := $(STAGE)/AppIcon.icns

## Assemble a real .app bundle. A bare SwiftPM binary has no bundle identity, and TCC keys the
## Microphone grant to bundle identity plus signature.
app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp "$(BUILD)" "$(CONTENTS)/MacOS/$(EXEC)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(CONTENTS)/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(MARKETING_VERSION)" "$(CONTENTS)/Info.plist"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@if [ -f "$(ICON_SRC)" ]; then \
		echo "generating AppIcon.icns"; \
		iconset="$(STAGE)/AppIcon.iconset"; \
		rm -rf "$$iconset"; mkdir -p "$$iconset"; \
		for size in 16 32 64 128 256 512 1024; do \
			sips -z $$size $$size "$(ICON_SRC)" --out "$$iconset/icon_$${size}x$${size}.png" >/dev/null 2>&1; \
		done; \
		for size in 16 32 64 128 256 512; do \
			sips -z $$((size*2)) $$((size*2)) "$(ICON_SRC)" --out "$$iconset/icon_$${size}x$${size}@2x.png" >/dev/null 2>&1; \
		done; \
		iconutil -c icns "$$iconset" -o "$(ICON_ICNS)" && cp "$(ICON_ICNS)" "$(CONTENTS)/Resources/AppIcon.icns"; \
	fi
	@xattr -cr "$(BUNDLE)"
	@codesign --force --sign "$(SIGN_ID)" \
		--entitlements Resources/$(EXEC).entitlements \
		--options runtime \
		--timestamp=none \
		"$(BUNDLE)"
	@echo "built $(BUNDLE)  [signed: $(SIGN_ID)]"

run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(BUNDLE)"

install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APPNAME)"
	@cp -R "$(BUNDLE)" "$(INSTALL_DIR)/$(APPNAME)"
	@echo "installed to $(INSTALL_DIR)/$(APPNAME)"

## Drop a compressed DMG on the Desktop, ready to share.
## The .app inside is signed with the same identity as `make app`.
dmg: app
	@echo "creating $(DMG_NAME)…"
	@rm -rf "$(DMG_STAGE)"
	@mkdir -p "$(DMG_STAGE)"
	@cp -R "$(BUNDLE)" "$(DMG_STAGE)/"
	@ln -sf /Applications "$(DMG_STAGE)/Applications"
	@rm -f "$(DMG_DEST)"
	@hdiutil create -volname "Prosetta" \
		-srcfolder "$(DMG_STAGE)" \
		-ov -format UDZO \
		"$(DMG_DEST)" >/dev/null
	@rm -rf "$(DMG_STAGE)"
	@echo "saved $(DMG_DEST)"

clean:
	@rm -rf "$(STAGE)"
	@swift package clean
