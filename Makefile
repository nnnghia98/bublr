APP_NAME  := Bublr
CONFIG    ?= Debug
DERIVED   := .build
APP       := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
BIN       := $(APP)/Contents/MacOS/$(APP_NAME)
VERSION   := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
# Stamped into Info.plist so a running copy can say which commit it is. Empty in an Xcode IDE build.
COMMIT    := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
INSTALLED := /Applications/$(APP_NAME).app
# Every bundle xcodebuild produces gets registered with LaunchServices, so a `.build/` copy would compete
# with the installed app for the name "Bublr" — that is exactly how a stale Debug build ended up launching.
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

.PHONY: all project build run test test-live render install reinstall package release clean

all: build

## Generate Bublr.xcodeproj from project.yml (requires: brew install xcodegen)
project:
	xcodegen generate

build: project
	xcodebuild -project Bublr.xcodeproj -scheme Bublr -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) BUBLR_COMMIT=$(COMMIT) build

## Launch the app. Extra flags: make run ARGS="--seed-demo"
run: build
	open $(APP) --args $(ARGS)

## Unit + overlay self-test. Live provider pages are skipped so CI stays independent of uptime.
test: build
	BUBLR_SKIP_LIVE=1 $(BIN) --selftest

## Full self-test, including loading Telegram, Zalo and Messenger sign-in pages.
test-live: build
	$(BIN) --selftest

## Render the real SwiftUI surfaces to /tmp/bublr-ui for offline visual review.
render: build
	$(BIN) --render-ui /tmp/bublr-ui

install: build
	rm -rf $(INSTALLED)
	cp -R $(APP) $(INSTALLED)
	-@$(LSREGISTER) -u "$(abspath $(APP))" >/dev/null 2>&1 || true
	-@$(LSREGISTER) -f $(INSTALLED) >/dev/null 2>&1 || true
	@echo "Installed $(APP_NAME) $(VERSION) ($(COMMIT)) -> $(INSTALLED)"

## Quit, rebuild Release, install, relaunch. The one command to run after merging.
reinstall:
	-@osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null || true
	-@pkill -f "$(INSTALLED)/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@sleep 1
	@$(MAKE) install CONFIG=Release
	@open $(INSTALLED)
	@echo "Running $$(/usr/libexec/PlistBuddy -c 'Print BublrCommit' $(INSTALLED)/Contents/Info.plist)" 

package: build
	mkdir -p dist
	rm -rf dist/$(APP_NAME).app
	cp -R $(APP) dist/
	ditto -c -k --keepParent dist/$(APP_NAME).app dist/$(APP_NAME)-$(VERSION).zip

## Build a Release app and zip it into dist/
release:
	$(MAKE) package CONFIG=Release

clean:
	rm -rf $(DERIVED) dist
	rm -rf Bublr.xcodeproj
