@testable import FabricCore
import Darwin
import Foundation
import Testing

@Suite(.serialized)
struct FoundationProcessRunnerTests {
    @Test("Child processes receive only allowlisted and explicit environment values")
    func environmentIsolation() async throws {
        let parentOnlyKey = "FABRIC_TEST_PARENT_ONLY"
        let explicitKey = "FABRIC_TEST_EXPLICIT"
        setenv(parentOnlyKey, "must-not-be-inherited", 1)
        defer { unsetenv(parentOnlyKey) }

        let result = try await FoundationProcessRunner().run(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                environment: [explicitKey: "allowed"],
                timeout: .seconds(10)
            )
        )

        #expect(result.succeeded)
        #expect(!result.standardOutput.contains("\(parentOnlyKey)="))
        #expect(result.standardOutput.contains("\(explicitKey)=allowed"))
        #expect(result.standardOutput.contains("PATH="))
        #expect(result.standardOutput.contains("HOME="))
    }
}
