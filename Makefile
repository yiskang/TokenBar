# Build order matters: the Rust staticlib must exist before swift build links.
# Run everything from the repo root (the -L path in Package.swift is relative).

.PHONY: all rust build run clean

all: build

rust:
	cargo build --release

build: rust
	swift build

run: rust
	swift run TokenBar

clean:
	cargo clean
	swift package clean

bundle: rust
	swift build -c release
	scripts/bundle.sh
