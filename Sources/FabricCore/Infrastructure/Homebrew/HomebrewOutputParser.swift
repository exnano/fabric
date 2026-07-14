import Foundation

/// Parsers are kept pure so Homebrew output compatibility can be covered by fixtures.
enum HomebrewOutputParser {
    static func formulaNames(from output: String) -> [String] {
        output
            .split(whereSeparator: \ .isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func installedFormulae(from output: String) -> [String: InstalledFormula] {
        var result: [String: InstalledFormula] = [:]

        for line in output.split(whereSeparator: \ .isNewline) {
            let components = line.split(whereSeparator: \ .isWhitespace).map(String.init)
            guard let name = components.first else { continue }
            result[name] = InstalledFormula(
                name: name,
                versions: Array(components.dropFirst())
            )
        }

        return result
    }

    static func pinnedFormulae(from output: String) -> Set<String> {
        Set(
            output
                .split(whereSeparator: \ .isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    static func serviceRecords(from data: Data) throws -> [HomebrewServiceRecord] {
        try JSONDecoder().decode([HomebrewServiceRecord].self, from: data)
    }
}
