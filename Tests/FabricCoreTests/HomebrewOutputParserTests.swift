@testable import FabricCore
import Foundation
import Testing

struct HomebrewOutputParserTests {
    @Test("Installed formula output preserves versioned names and versions")
    func installedFormulae() {
        let output = """
        mailpit 1.30.4
        php@8.4 8.4.12_1
        postgresql@17 17.5 17.6
        """

        let parsed = HomebrewOutputParser.installedFormulae(from: output)

        #expect(parsed["mailpit"]?.versions == ["1.30.4"])
        #expect(parsed["php@8.4"]?.versions == ["8.4.12_1"])
        #expect(parsed["postgresql@17"]?.versions == ["17.5", "17.6"])
    }

    @Test("Homebrew service JSON maps exit_code correctly")
    func serviceRecords() throws {
        let data = Data(
            """
            [
              {
                "name": "mailpit",
                "status": "started",
                "user": "developer",
                "file": "/Users/developer/Library/LaunchAgents/homebrew.mxcl.mailpit.plist",
                "exit_code": null
              },
              {
                "name": "nginx",
                "status": "error",
                "user": "developer",
                "file": null,
                "exit_code": 1
              }
            ]
            """.utf8
        )

        let records = try HomebrewOutputParser.serviceRecords(from: data)

        #expect(records.count == 2)
        #expect(records[0].name == "mailpit")
        #expect(records[0].exitCode == nil)
        #expect(records[1].name == "nginx")
        #expect(records[1].exitCode == 1)
    }
}
