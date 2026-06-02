.PHONY: contrib install-hooks generate format lint-format test build clean where authenticate dmg install uninstall

SWIFT_FORMAT_PATHS = App Packages
# Extra args appended to the xcodebuild line. CI sets this to disable signing
# (CODE_SIGNING_ALLOWED=NO) since the runner has no Developer ID certs.
XCODEBUILD_FLAGS ?=

PROJECT = SlackAuth.xcodeproj
SCHEME = SlackAuth
CONFIG = Debug
# Fixed build location so the .app/binary paths are static (no awk needed).
DERIVED = .build-xcode
# The product is "Slack Auth.app" (PRODUCT_NAME has a space); every use of
# $(APP)/$(BIN) below is quoted accordingly.
APP = $(DERIVED)/Build/Products/$(CONFIG)/Slack Auth.app
BIN = $(APP)/Contents/MacOS/Slack Auth

# Where `make install` puts things — the same layout a Homebrew cask produces:
# the .app under /Applications, and a `slack-auth` symlink to the in-bundle
# binary in a directory on PATH (Homebrew's bin).
APP_INSTALL_DIR ?= /Applications
BIN_INSTALL_DIR ?= $(shell brew --prefix 2>/dev/null || echo /usr/local)/bin

contrib:
	@echo "Installing development dependencies..."
	brew install xcodegen
	@$(MAKE) install-hooks
	@$(MAKE) generate

install-hooks:
	@git config core.hooksPath .githooks
	@echo "Configured git hooks to use .githooks/"

generate:
	xcodegen generate

format:
	swift-format format --in-place --recursive --configuration .swift-format $(SWIFT_FORMAT_PATHS)

lint-format:
	swift-format lint --strict --recursive --configuration .swift-format $(SWIFT_FORMAT_PATHS)

test:
	swift test --package-path Packages/SlackAuthKit

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS) build

# Delete build artifacts. Leaves the generated .xcodeproj (cheap to regenerate).
clean:
	rm -rf $(DERIVED)

# Print the built binary's path so you can run it directly.
where:
	@echo "$(BIN)"

# Build + launch the GUI login window. Equivalent to running the app in Xcode.
authenticate: build
	open -n -W "$(APP)"

# Build a signed + notarized + stapled .dmg. Needs a Developer ID Application
# identity and notary credentials — see scripts/build-dmg.sh for the env vars.
dmg:
	scripts/build-dmg.sh

# Install locally the way a Homebrew cask would: copy the .app to /Applications
# and symlink the in-bundle binary onto PATH as `slack-auth`. Build it signed
# (the default, Developer ID) so the Keychain item stays accessible across runs.
install: build
	rm -rf "$(APP_INSTALL_DIR)/Slack Auth.app"
	ditto "$(APP)" "$(APP_INSTALL_DIR)/Slack Auth.app"
	mkdir -p "$(BIN_INSTALL_DIR)"
	ln -sf "$(APP_INSTALL_DIR)/Slack Auth.app/Contents/MacOS/Slack Auth" "$(BIN_INSTALL_DIR)/slack-auth"
	@echo "Installed Slack Auth.app -> $(APP_INSTALL_DIR) and slack-auth -> $(BIN_INSTALL_DIR)"

uninstall:
	rm -rf "$(APP_INSTALL_DIR)/Slack Auth.app"
	rm -f "$(BIN_INSTALL_DIR)/slack-auth"
	@echo "Removed Slack Auth.app and the slack-auth symlink."
