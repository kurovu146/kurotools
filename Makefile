CARGO_TARGET := crates/target
LIB := $(CARGO_TARGET)/release/libktranslate_ffi.a
STAMP := $(CARGO_TARGET)/.ffi-hash
export MACOSX_DEPLOYMENT_TARGET := 13.0

.PHONY: rust build test app saver clean

rust:
	cargo build --release --target-dir $(CARGO_TARGET)
	@# SwiftPM không coi .a là build input, và `touch` một file Swift KHÔNG ép
	@# nó relink (đã đo: swift-driver quyết định theo interface hash của module,
	@# không theo mtime hay nội dung). Cách duy nhất chắc chắn là vứt .build đi
	@# khi .a thật sự đổi — nên chỉ trả giá rebuild khi Rust có thay đổi thật.
	@new=$$(shasum -a 256 $(LIB) | cut -d' ' -f1); \
	 old=$$(cat $(STAMP) 2>/dev/null); \
	 if [ "$$new" != "$$old" ]; then \
	   echo "ffi changed -> forcing a clean Swift build"; \
	   rm -rf .build; \
	   echo "$$new" > $(STAMP); \
	 fi

build: rust
	swift build

test: rust
	cargo test --workspace --target-dir $(CARGO_TARGET)
	swift test

app:
	./scripts/bundle-app.sh

saver:
	./scripts/bundle-saver.sh

clean:
	cargo clean --target-dir $(CARGO_TARGET)
	rm -rf .build
