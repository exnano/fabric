import Foundation

public enum FabricError: LocalizedError, Sendable {
    case homebrewNotFound
    case invalidFormula(String)
    case commandFailed(command: String, exitCode: Int32, message: String)
    case catalogItemUnavailable(String)
    case duplicateService(String)
    case invalidServiceName
    case serviceNotFound
    case packageVersionMissing(String)
    case persistence(String)
    case logUnavailable

    public var errorDescription: String? {
        switch self {
        case .homebrewNotFound:
            "Homebrew was not found in /opt/homebrew or /usr/local. Install Homebrew before adding a formula-backed service."
        case let .invalidFormula(formula):
            "“\(formula)” is not a valid Homebrew formula identifier."
        case let .commandFailed(command, exitCode, message):
            "\(command) exited with status \(exitCode): \(message)"
        case let .catalogItemUnavailable(item):
            "The catalog item “\(item)” is no longer available. Refresh the catalog and try again."
        case let .duplicateService(name):
            "\(name) is already registered. The Homebrew bridge supports one instance per formula in this release."
        case .invalidServiceName:
            "Enter a name for this service."
        case .serviceNotFound:
            "This service is no longer registered in Fabric."
        case let .packageVersionMissing(formula):
            "Homebrew installed \(formula), but Fabric could not determine its installed version."
        case let .persistence(message):
            "Fabric could not save its service registry: \(message)"
        case .logUnavailable:
            "No readable log file was found for this service."
        }
    }
}
