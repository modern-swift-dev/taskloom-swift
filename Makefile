# Override with a shell-quoted file list to check only changed Swift files.
SWIFT_FILES ?= .

SHELL := /bin/bash

SCHEME ?= TaskLoom-Package
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest
TVOS_DESTINATION ?= platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest
WATCHOS_DESTINATION ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest
VISIONOS_DESTINATION ?= platform=visionOS Simulator,name=Apple Vision Pro,OS=latest

.PHONY: test test-swift test-macos test-linux test-ios test-tvos test-watchos test-visionos test-apple documentation

test test-swift test-macos:
	swift test

test-linux:
	docker run --rm -v "$(CURDIR):/workspace" -w /workspace swift:6.3 swift test --scratch-path .build/linux

test-ios:
	xcodebuild test -scheme "$(SCHEME)" -destination "$(IOS_DESTINATION)"

test-tvos:
	xcodebuild test -scheme "$(SCHEME)" -destination "$(TVOS_DESTINATION)"

test-watchos:
	xcodebuild test -scheme "$(SCHEME)" -destination "$(WATCHOS_DESTINATION)"

test-visionos:
	xcodebuild test -scheme "$(SCHEME)" -destination "$(VISIONOS_DESTINATION)"

test-apple:
	$(MAKE) test-macos
	$(MAKE) test-ios
	$(MAKE) test-tvos
	$(MAKE) test-watchos
	$(MAKE) test-visionos

documentation:
	bash scripts/build-documentation.sh

.PHONY: setup format lint

setup:
	brew bundle install
	mint bootstrap
	lefthook install

format:
	mint run --no-install nicklockwood/SwiftFormat $(SWIFT_FILES) --config .swiftformat --quiet
	mint run --no-install realm/SwiftLint lint --config .swiftlint.yml --fix --quiet --force-exclude $(SWIFT_FILES)

lint: lint-workflows
	mint run --no-install realm/SwiftLint lint --config .swiftlint.yml --quiet --force-exclude $(SWIFT_FILES)

.PHONY: lint-workflows

lint-workflows:
	actionlint
