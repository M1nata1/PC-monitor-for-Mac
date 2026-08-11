BINARY   := PCHealth
APP_NAME := PC Health
BUILD    := .build/release
APP      := $(BUILD)/$(APP_NAME).app

.PHONY: build app run dump json bench icon screenshots install clean

## Compile the release binary
build:
	swift build -c release

## Redraw the app icon (Resources/AppIcon.icns + a full-size PNG preview)
icon:
	swift Scripts/GenerateIcon.swift Resources/AppIcon.icns

Resources/AppIcon.icns: Scripts/GenerateIcon.swift
	swift Scripts/GenerateIcon.swift Resources/AppIcon.icns

## Wrap the binary in a .app bundle (needed for the menu bar item and Dock icon)
app: build Resources/AppIcon.icns
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BUILD)/$(BINARY)" "$(APP)/Contents/MacOS/$(BINARY)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "$(APP)" >/dev/null 2>&1 || true
	@# Dock and Finder cache icons per bundle path; nudge them to re-read it.
	@touch "$(APP)"
	@echo "built $(APP)"

## Build the bundle and launch it
run: app
	open "$(APP)"

## One-shot text reading in the terminal
dump: build
	@$(BUILD)/$(BINARY) --dump

## One-shot reading as JSON
json: build
	@$(BUILD)/$(BINARY) --json

## Timing of a sampling pass
bench: build
	@$(BUILD)/$(BINARY) --bench

## Re-render the README screenshots into docs/screenshots
screenshots: build
	$(BUILD)/$(BINARY) --screenshots docs/screenshots

## Copy the bundle to /Applications
install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" "/Applications/$(APP_NAME).app"
	@echo "installed /Applications/$(APP_NAME).app"

clean:
	swift package clean
	rm -rf .build
