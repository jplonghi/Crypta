#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
package=Packages/CryptaCore
sodium="$package/.build/checkouts/swift-sodium/Clibsodium.xcframework/macos-arm64_arm64e_x86_64"
build="$package/.build/fuzz"
mkdir -p "$build/module-cache"
sanitizer_flags=(-g)
if [ "${CRYPTA_FUZZ_ASAN:-0}" = 1 ]; then sanitizer_flags=(-g -sanitize=address); fi
swiftc -swift-version 6 -parse-as-library "${sanitizer_flags[@]}" \
  -module-cache-path "$build/module-cache" -I "$sodium/Headers/Clibsodium" \
  "$package"/Sources/CryptaCore/*.swift "$package"/Sources/CryptaCore/*/*.swift "$package/Tests/Fuzz/ParserFuzz.swift" \
  "$sodium/libsodium.a" -o "$build/parser-fuzz"
"$build/parser-fuzz" "${1:-20000}" \
  "$package/Tests/CryptaCoreTests/Fixtures/reference-v1.crypta" \
  "$package/Tests/CryptaCoreTests/Fixtures/reference-payload.json"
