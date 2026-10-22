# LiteDisplay — developer commands. Build products stay outside the repository (see CLAUDE.md).
SHELL := /bin/bash
export PATH := /opt/homebrew/bin:$(PATH)

PROJECT   := LiteDisplay.xcodeproj
SCHEME    := LiteDisplay
DEST      := platform=macOS,arch=arm64
DERIVED   ?= $(or $(TMPDIR),/tmp)/LiteDisplay-DerivedData
APP       := $(DERIVED)/Build/Products/Debug/LiteDisplay.app
XCB       := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath "$(DERIVED)" CODE_SIGN_IDENTITY=-

.PHONY: generate build run stop test lint format audit modes install release clean

generate:            ## Regenerate the Xcode project from project.yml
	xcodegen generate

build: generate      ## Debug build (ad-hoc signed)
	$(XCB) -configuration Debug build | tail -20

run: build stop      ## Build and launch the app
	open "$(APP)"

stop:                ## Quit a running instance
	-pkill -x LiteDisplay 2>/dev/null || true

test: generate       ## Run Swift Testing suites
	$(XCB) -configuration Debug test 2>&1 | grep -E "Test Suite|Test Case|passed|failed|error:" | tail -40

lint:                ## SwiftLint (strict) + SwiftFormat lint
	swiftlint lint --strict --quiet --config .swiftlint.yml
	swiftformat LiteDisplay LiteDisplayTests --lint --quiet

format:              ## Apply SwiftFormat
	swiftformat LiteDisplay LiteDisplayTests --quiet

audit:               ## Project code audit (lint, analyzer, safety scans)
	.claude/skills/code-audit/scripts/audit.sh

modes:               ## Dump every display and its modes
	swift scripts/dump-modes.swift

install: build stop  ## Copy the app to /Applications (stable path for the login item)
	rm -rf /Applications/LiteDisplay.app && ditto "$(APP)" /Applications/LiteDisplay.app && open /Applications/LiteDisplay.app

release:             ## Release build zipped into dist/
	scripts/release.sh

clean:
	rm -rf "$(DERIVED)"
