set shell := ["bash", "-uc"]

NAME := "vug"
CRYSTAL_VERSION := "1.18.0"
VERSION := `grep '^version:' shard.yml | awk '{print $2}'`

os := `uname -s`
arch := `uname -m`

home := env_var("HOME")
CACHE_DIR := home + "/.cache/vug/crystal"
CRYSTAL_DIR := CACHE_DIR + "/crystal-" + CRYSTAL_VERSION + "-" + os + "-" + arch

crystal_bin := if os == "linux" {
    CRYSTAL_DIR + "/bin/crystal"
} else if os == "Darwin" {
    "$(which crystal 2>/dev/null || echo '/usr/local/bin/crystal')"
} else {
    CRYSTAL_DIR + "/bin/crystal"
}

FINAL_CRYSTAL := if os == "Darwin" {
    "$(which crystal 2>/dev/null || echo 'crystal')"
} else {
    "$(if command -v crystal >/dev/null 2>&1; then echo 'crystal'; elif test -x \"" + CRYSTAL_DIR + "/bin/crystal\"; then echo \"" + CRYSTAL_DIR + "/bin/crystal\"; else echo 'crystal'; fi)"
}

default: test

check-deps:
    @echo "Checking dependencies..."
    @SYSTEM_CRYSTAL=$(which crystal 2>/dev/null || echo ""); \
    if [ -n "$SYSTEM_CRYSTAL" ] && [ -x "$SYSTEM_CRYSTAL" ]; then \
        echo "✓ Found system Crystal: $SYSTEM_CRYSTAL"; \
        $SYSTEM_CRYSTAL --version | head -1; \
    else \
        echo "❌ Error: Crystal compiler not found"; \
        echo ""; \
        echo "Install Crystal:"; \
        echo "  Linux:   curl -fsSL https://crystal-lang.org/install.sh | bash"; \
        echo "  macOS:   brew install crystal"; \
        echo "  Or use:  nix develop"; \
        exit 1; \
    fi
    @if command -v shards >/dev/null 2>&1; then \
        echo "✓ shards: $$(shards --version)"; \
    else \
        echo "❌ Error: shards not found"; \
        exit 1; \
    fi

install:
    @echo "Installing dependencies..."
    shards install
    @echo "✓ Dependencies installed"

build: check-deps install
    @echo "Building library..."
    {{FINAL_CRYSTAL}} build --no-codegen src/{{NAME}}.cr 2>&1 | head -50
    @echo "✓ Build successful"

test: check-deps install
    @echo "Running tests..."
    {{FINAL_CRYSTAL}} spec --verbose
    @echo "✓ Tests passed"

lint: check-deps install
    @echo "Running linter..."
    @if command -v ameba >/dev/null 2>&1; then \
        ameba src/ spec/; \
    elif [ -f "bin/ameba" ]; then \
        ./bin/ameba src/ spec/; \
    else \
        echo "Ameba not found, running via crystal..."; \
        {{FINAL_CRYSTAL}} run bin/ameba.cr -- src/ spec/; \
    fi

format:
    @echo "Formatting code..."
    {{FINAL_CRYSTAL}} tool format src/ spec/
    @echo "✓ Formatted"

format-check:
    @echo "Checking formatting..."
    @if {{FINAL_CRYSTAL}} tool format --check src/ spec/; then \
        echo "✓ Formatting is correct"; \
    else \
        echo "❌ Formatting issues found. Run 'just format' to fix."; \
        exit 1; \
    fi

check: format-check lint test
    @echo "✓ All checks passed"

clean:
    rm -rf .crystal
    rm -rf lib/
    rm -rf bin/
    @echo "✓ Cleaned build artifacts"

reinstall: clean install

rebuild: clean build

nix-build:
    @echo "Building with nix develop..."
    nix develop . --command crystal build --no-codegen src/{{NAME}}.cr
    @echo "✓ Build successful"

nix-test:
    @echo "Testing with nix develop..."
    nix develop . --command crystal spec --verbose
    @echo "✓ Tests passed"

nix-lint:
    @echo "Linting with nix develop..."
    nix develop . --command crystal run bin/ameba.cr -- src/ spec/
    @echo "✓ Lint passed"

nix-check: nix-build nix-lint nix-test

help:
    @echo "{{NAME}} - Favicon fetching library"
    @echo ""
    @echo "Usage: just [target]"
    @echo ""
    @echo "Targets:"
    @echo "  default       - Run tests (default)"
    @echo "  check-deps    - Check for required dependencies"
    @echo "  install       - Install shard dependencies"
    @echo "  build         - Build check (no codegen)"
    @echo "  test          - Run specs"
    @echo "  lint          - Run ameba linter"
    @echo "  format        - Format source code"
    @echo "  format-check  - Check formatting without modifying"
    @echo "  check         - Run format-check, lint, and test"
    @echo "  clean         - Remove build artifacts"
    @echo "  reinstall     - Clean and reinstall dependencies"
    @echo "  rebuild       - Clean and rebuild"
    @echo "  nix-build     - Build using nix develop"
    @echo "  nix-test      - Test using nix develop"
    @echo "  nix-lint      - Lint using nix develop"
    @echo "  nix-check     - Run all checks via nix"
    @echo "  help          - Show this help"
    @echo ""
    @echo "Platform: {{os}}-{{arch}}"
    @echo "Version: v{{VERSION}}"
