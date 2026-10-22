# DockFlip — build with the Command Line Tools only (xcode-select --install).
#
#   make            build build/DockFlip.app
#   make install    create the local signing certificate (first time only),
#                   build, and install to /Applications
#   make run        build and run from build/
#   make test       run unit tests
#   make clean

APP_NAME  := DockFlip
BUNDLE_ID ?= io.github.dockflip.DockFlip
VERSION   ?= 0.3.0
BUILD_NUM ?= 1
CONFIG    ?= release
SIGN_ID   ?= DockFlip Signing
SIGN_KEYCHAIN := $(HOME)/Library/Keychains/dockflip-signing.keychain-db
SIGN_PASSFILE := $(HOME)/Library/Application Support/DockFlip/signing-keychain-password

BUILD_DIR := build
APP       := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR ?= /Applications

.PHONY: all build app sign cert install run test clean

all: app

build:
	swift build -c $(CONFIG)

app: build
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp "$$(swift build -c $(CONFIG) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	@sed -e 's/__VERSION__/$(VERSION)/' \
	     -e 's/__BUILD__/$(BUILD_NUM)/' \
	     -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/' \
	     Resources/Info.plist > "$(APP)/Contents/Info.plist"
	@cp -R Resources/en.lproj "$(APP)/Contents/Resources/"
	@cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	@$(MAKE) --no-print-directory sign
	@echo "Built $(APP)"

# Signs with the local self-signed identity when it exists, so macOS keeps the
# Accessibility permission across rebuilds. Falls back to ad-hoc signing.
# The identity lives in its own keychain (see scripts/create-signing-cert.sh).
sign:
	@if [ -f "$(SIGN_KEYCHAIN)" ] && [ -f "$(SIGN_PASSFILE)" ] \
	   && security unlock-keychain -p "$$(cat "$(SIGN_PASSFILE)")" "$(SIGN_KEYCHAIN)" 2>/dev/null \
	   && security find-identity -v -p codesigning "$(SIGN_KEYCHAIN)" | grep -q "\"$(SIGN_ID)\""; then \
		codesign --force --timestamp=none --keychain "$(SIGN_KEYCHAIN)" --sign "$(SIGN_ID)" "$(APP)"; \
		echo "Signed with \"$(SIGN_ID)\""; \
	else \
		codesign --force --sign - "$(APP)"; \
		echo "warning: \"$(SIGN_ID)\" not found, signed ad-hoc."; \
		echo "         Run 'make cert' once so permissions survive rebuilds."; \
	fi

cert:
	@./scripts/create-signing-cert.sh "$(SIGN_ID)"

install: cert app
	@-pkill -x "$(APP_NAME)" 2>/dev/null; sleep 0.5
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP)" "$(INSTALL_DIR)/"
	@echo "Installed $(INSTALL_DIR)/$(APP_NAME).app"
	@open "$(INSTALL_DIR)/$(APP_NAME).app"

run: app
	@-pkill -x "$(APP_NAME)" 2>/dev/null; sleep 0.5
	@open "$(APP)"

test:
	swift test --disable-xctest

clean:
	rm -rf .build "$(BUILD_DIR)"
