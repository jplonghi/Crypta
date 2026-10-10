import Foundation
import Testing
@testable import CryptaCore

@Suite struct FormatTests {
    @Test func strictJSON() throws {
        for text in [#"{"a":1,"a":2}"#, #"{"a":1,"\u0061":2}"#, #"{"a":01}"#,
                     #"{"a":NaN}"#, #"{"a":1e9999}"#, #"{"a":1,}"#, #"{"a":"\uD800"}"#,
                     #"{"a":"\x"}"#, #"{"a":+1}"#, #"{"a":.5}"#, #"{"a":1.}"#,
                     #"{"a":[1,]}"#, "{} true", "[]", "null", "{", ""] {
            #expect(throws: (any Error).self) { try JSONValidator.validate(Data(text.utf8)) }
        }
        try JSONValidator.validate(Data(#"{"bool":true,"null":null,"number":-0.1e+2,"text":"\uD83D\uDDDD","array":[1,2]}"#.utf8))
        #expect(throws: VaultError.invalidPayload) { try JSONValidator.validate(Data([123,34,255,34,58,49,125])) }
        let deep = "{\"a\":" + String(repeating: "[", count: 16) + "0" + String(repeating: "]", count: 16) + "}"
        #expect(throws: VaultError.resourceLimit) { try JSONValidator.validate(Data(deep.utf8)) }
        let largeArray = "{\"a\":[" + Array(repeating: "0", count: 10_001).joined(separator: ",") + "]}"
        #expect(throws: VaultError.resourceLimit) { try JSONValidator.validate(Data(largeArray.utf8)) }
        let largeString = "{\"a\":\"" + String(repeating: "x", count: 1_048_577) + "\"}"
        #expect(throws: VaultError.resourceLimit) { try JSONValidator.validate(Data(largeString.utf8)) }
    }

    @Test func deterministicMalformedCorpus() throws {
        // Reproducible parser smoke fuzzing; no KDF or filesystem effects.
        var state: UInt64 = 0x637279707461
        func next() -> UInt8 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: state >> 32)
        }
        for index in 0..<5000 {
            let bytes = Data((0..<(index % 512)).map { _ in next() })
            _ = try? VaultFormat.parse(bytes)
            _ = try? JSONValidator.validate(bytes)
        }
    }
}
