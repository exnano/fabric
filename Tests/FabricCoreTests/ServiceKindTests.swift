@testable import FabricCore
import Testing

struct ServiceKindTests {
    @Test("Formula families are discovered without hard-coding every version")
    func formulaMatching() {
        #expect(ServiceKind.kind(forFormula: "mariadb@11.4") == .mariaDB)
        #expect(ServiceKind.kind(forFormula: "mysql@8.4") == .mySQL)
        #expect(ServiceKind.kind(forFormula: "postgresql@17") == .postgreSQL)
        #expect(ServiceKind.kind(forFormula: "redis") == .redis)
        #expect(ServiceKind.kind(forFormula: "valkey") == .valkey)
        #expect(ServiceKind.kind(forFormula: "owner/tap/typesense-server") == .typesense)
        #expect(ServiceKind.kind(forFormula: "nginx") == .nginx)
        #expect(ServiceKind.kind(forFormula: "caddy") == .caddy)
        #expect(ServiceKind.kind(forFormula: "unrelated") == nil)
    }

    @Test("Multi-port services expose named endpoints")
    func namedEndpoints() {
        #expect(ServiceKind.mailpit.defaultEndpoints.map(\.name) == ["SMTP", "Web UI"])
        #expect(ServiceKind.mailpit.defaultEndpoints.map(\.port) == [1_025, 8_025])
        #expect(ServiceKind.caddy.defaultEndpoints.map(\.port) == [80, 443])
    }
}
