CARGO_TARGET := crates/target
BRIDGE := Sources/Translate/KTranslateBridge.swift
export MACOSX_DEPLOYMENT_TARGET := 13.0

.PHONY: rust build test app clean

rust:
	cargo build --release --target-dir $(CARGO_TARGET)
	@# SwiftPM không coi libktranslate_ffi.a là build input: nếu chỉ Rust đổi
	@# thì `swift build` báo "Build complete" trong 0.15s và chạy binary CŨ.
	@# Chạm vào file cầu FFI là cách rẻ nhất buộc nó relink.
	@test -f $(BRIDGE) && touch $(BRIDGE) || true

build: rust
	swift build

test: rust
	cargo test --workspace --target-dir $(CARGO_TARGET)
	swift test

app:
	./scripts/bundle-app.sh

clean:
	cargo clean --target-dir $(CARGO_TARGET)
	rm -rf .build
