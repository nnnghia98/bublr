APP_NAME  := Bublr
CONFIG    ?= Debug
DERIVED   := .build
APP       := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
BIN       := $(APP)/Contents/MacOS/$(APP_NAME)
VERSION   := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)

.PHONY: all project build run test test-live render install package release clean

all: build

## Generate Bublr.xcodeproj from project.yml (requires: brew install xcodegen)
project:
	xcodegen generate

build: project
	xcodebuild -project Bublr.xcodeproj -scheme Bublr -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) build

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
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/

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
