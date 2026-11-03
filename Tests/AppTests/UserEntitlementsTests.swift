import Foundation
import Testing
import Vapor
import VaporTesting

@testable import App

private final class StubEntitlements: EntitlementsServing, @unchecked Sendable {
  private let lock = NSLock()
  var records: [EntitlementRecord]
  var audit: [AuditEntry]
  var readError: EntitlementsError?
  var auditError: EntitlementsError?
  var setError: EntitlementsError?
  private(set) var reads = 0
  private(set) var sets: [(key: String, request: OverrideRequest, token: String)] = []
  private(set) var removals: [(key: String, reason: String)] = []

  init(records: [EntitlementRecord] = [], audit: [AuditEntry] = []) {
    self.records = records
    self.audit = audit
  }

  func read(userID: String, accessToken: String) async throws -> [EntitlementRecord] {
    lock.withLock { reads += 1 }
    if let readError { throw readError }
    return records
  }

  func recentAudit(userID: String, accessToken: String) async throws -> [AuditEntry] {
    if let auditError { throw auditError }
    return audit
  }

  func setOverride(
    userID: String, key: String, request: OverrideRequest, accessToken: String
  ) async throws {
    if let setError { throw setError }
    lock.withLock { sets.append((key, request, accessToken)) }
  }

  func removeOverride(userID: String, key: String, reason: String, accessToken: String)
    async throws
  {
    lock.withLock { removals.append((key, reason)) }
  }
}

private func grant(
  _ source: String, value: EntitlementValue? = nil, product: String? = nil, quantity: Int? = nil,
  reason: String? = nil, setBy: String? = nil
) -> GrantLine {
  GrantLine(
    source: source, value: value, mode: nil, productId: product, quantity: quantity,
    reason: reason, setBy: setBy, validUntil: nil)
}

/// Free key: tier value 2, no payment behind it.
private let freeKey = EntitlementRecord(
  key: "initiative.connections", type: "limit", default: .count(2),
  tierGrants: [TierGrantLine(tierId: "free", value: .count(2), source: "default")],
  grants: [], override: nil, paid: .count(0), payments: [], effective: .count(2))

/// Paid key: tier 5 plus two purchased units of 5 = effective 10, paid value 10.
private let paidKey = EntitlementRecord(
  key: "initiative.theme_slots", type: "limit", default: .count(5),
  tierGrants: [TierGrantLine(tierId: "free", value: .count(5), source: "default")],
  grants: [
    grant("stripe_purchase", value: .count(5), product: "theme-pack", quantity: 1),
    grant("stripe_purchase", value: .count(5), product: "theme-pack", quantity: 1),
  ],
  override: grant("admin", value: .count(8), reason: "perk", setBy: "ada"),
  paid: .count(10),
  payments: [
    grant("stripe_purchase", value: .count(5), product: "theme-pack", quantity: 1),
    grant("stripe_purchase", value: .count(5), product: "theme-pack", quantity: 1),
  ], effective: .count(8))

private func admin(_ roles: [String] = ["admin"]) -> SessionUser {
  SessionUser(
    sub: "auth0|admin", name: "Ada", email: "ada@example.com", roles: roles,
    accessToken: "admin-token", expiry: Date().addingTimeInterval(3600))
}

private func withStub(
  roles: [String] = ["admin"], _ stub: StubEntitlements,
  _ body: (Application) async throws -> Void
) async throws {
  try await withApp(configure: configure) { app in
    app.entitlementsServiceOverride = stub
    let user = admin(roles)
    app.sessionUserProvider = { _ in user }
    try await body(app)
  }
}

private let form: HTTPHeaders = ["Content-Type": "application/x-www-form-urlencoded"]

@Suite("User entitlements page", .serialized)
struct UserEntitlementsTests {
  @Test("a non-admin gets 403 and no call reaches entitlements-api")
  func nonAdminForbidden() async throws {
    let stub = StubEntitlements(records: [freeKey])
    try await withStub(roles: ["user"], stub) { app in
      try await app.testing().test(.GET, "users/u1/entitlements") { res in
        #expect(res.status == .forbidden)
      }
      #expect(stub.reads == 0)
    }
  }

  @Test("every source of a value is shown: tier, two purchased grants, override, effective")
  func explainsValue() async throws {
    let stub = StubEntitlements(records: [paidKey])
    try await withStub(stub) { app in
      try await app.testing().test(.GET, "users/u1/entitlements") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("initiative.theme_slots"))
        #expect(body.contains("free (default): 5"))
        #expect(body.components(separatedBy: "stripe_purchase theme-pack x1: 5").count - 1 >= 2)
        #expect(body.contains("perk"))
        #expect(body.contains("<strong>8</strong>"))
        #expect(body.contains("Reduces a paid value"))
      }
    }
  }

  @Test("recent audit entries are listed in the order the service returns them")
  func showsAudit() async throws {
    let audit = [
      AuditEntry(
        at: "2026-11-02T10:00:00Z", actor: "ada", action: "set",
        subject: "u1/initiative.theme_slots",
        reason: "reason-newer", before: .count(8), after: .count(9)),
      AuditEntry(
        at: "2026-11-01T10:00:00Z", actor: "bob", action: "set",
        subject: "u1/initiative.theme_slots",
        reason: "reason-older", before: .count(5), after: .count(8)),
    ]
    let stub = StubEntitlements(records: [paidKey], audit: audit)
    try await withStub(stub) { app in
      try await app.testing().test(.GET, "users/u1/entitlements") { res in
        let body = res.body.string
        let second = body.range(of: "reason-newer")?.lowerBound
        let first = body.range(of: "reason-older")?.lowerBound
        #expect(second != nil && first != nil && second! < first!)
        #expect(body.contains("8 -&gt; 9") || body.contains("8 -> 9"))
      }
    }
  }

  @Test("entitlements-api down: message only, no edit controls")
  func unavailable() async throws {
    let stub = StubEntitlements(records: [freeKey])
    stub.readError = .unavailable
    try await withStub(stub) { app in
      try await app.testing().test(.GET, "users/u1/entitlements") { res in
        let body = res.body.string
        #expect(body.contains("not available right now"))
        #expect(!body.contains("<form class=\"form\""))
        #expect(!body.contains("initiative.connections"))
      }
    }
  }

  @Test("audit read failing hides only the history")
  func auditUnavailable() async throws {
    let stub = StubEntitlements(records: [freeKey])
    stub.auditError = .unavailable
    try await withStub(stub) { app in
      try await app.testing().test(.GET, "users/u1/entitlements") { res in
        let body = res.body.string
        #expect(body.contains("initiative.connections"))
        #expect(body.contains("change history is not available"))
      }
    }
  }
}

@Suite("Override forms", .serialized)
struct OverrideFormTests {
  private func post(
    _ app: Application, _ path: String, _ body: String, check: (TestingHTTPResponse) throws -> Void
  ) async throws {
    try await app.testing().test(.POST, path, headers: form, body: ByteBuffer(string: body)) {
      try check($0)
    }
  }

  @Test("missing reason is rejected with no service call")
  func missingReason() async throws {
    let stub = StubEntitlements(records: [freeKey])
    try await withStub(stub) { app in
      try await post(
        app, "users/u1/entitlements/initiative.connections/override", "value=3&reason=%20"
      ) { res in
        #expect(res.status == .unprocessableEntity)
        #expect(res.body.string.contains("A reason is required."))
      }
      #expect(stub.sets.isEmpty)
    }
  }

  @Test("raising an unpaid key submits with the admin's own token")
  func raiseSubmits() async throws {
    let stub = StubEntitlements(records: [freeKey])
    try await withStub(stub) { app in
      try await post(
        app, "users/u1/entitlements/initiative.connections/override", "value=5&reason=perk"
      ) { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location) == "/users/u1/entitlements")
      }
      #expect(stub.sets.count == 1)
      #expect(stub.sets.first?.request.value == .count(5))
      #expect(stub.sets.first?.request.paidReductionReference == nil)
      #expect(stub.sets.first?.token == "admin-token")
    }
  }

  @Test("lowering an unpaid key shows only the ordinary confirmation")
  func loweringUnpaid() async throws {
    let stub = StubEntitlements(records: [freeKey])
    try await withStub(stub) { app in
      try await post(
        app, "users/u1/entitlements/initiative.connections/override", "value=1&reason=penalty"
      ) { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("This lowers the value from 2 to 1"))
        #expect(!body.contains("ack-checkbox"))
      }
      #expect(stub.sets.isEmpty)
    }
  }

  @Test("lowering a paid key shows the warning, payments, and a disabled submit")
  func loweringPaid() async throws {
    let stub = StubEntitlements(records: [paidKey])
    try await withStub(stub) { app in
      try await post(
        app, "users/u1/entitlements/initiative.theme_slots/override", "value=3&reason=abuse"
      ) { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("Reducing something this user paid for"))
        #expect(body.contains("legal and financial liability"))
        #expect(body.contains("refunding in Stripe"))
        #expect(body.contains("stripe_purchase theme-pack x1: 5"))
        #expect(body.contains("<strong>10</strong>"))
        #expect(body.contains("<strong>3</strong>"))
        #expect(body.contains("id=\"ack-checkbox\""))
        let submit = try #require(body.range(of: "id=\"ack-submit\""))
        let tag = body[submit.lowerBound...].prefix(while: { $0 != ">" })
        #expect(tag.contains("disabled"))
      }
      #expect(stub.sets.isEmpty)
    }
  }

  @Test("a confirmed paid reduction without acknowledgment and reference is refused")
  func paidWithoutAcknowledgment() async throws {
    let stub = StubEntitlements(records: [paidKey])
    try await withStub(stub) { app in
      let path = "users/u1/entitlements/initiative.theme_slots/override"
      try await post(app, path, "value=3&reason=abuse&confirmed=yes&reference=T-1") { res in
        #expect(res.status == .unprocessableEntity)
      }
      try await post(app, path, "value=3&reason=abuse&confirmed=yes&acknowledged=yes") { res in
        #expect(res.status == .unprocessableEntity)
      }
      #expect(stub.sets.isEmpty)
    }
  }

  @Test("an acknowledged paid reduction sends the reference to the service")
  func paidAcknowledged() async throws {
    let stub = StubEntitlements(records: [paidKey])
    try await withStub(stub) { app in
      try await post(
        app, "users/u1/entitlements/initiative.theme_slots/override",
        "value=3&reason=abuse&confirmed=yes&acknowledged=yes&reference=T-1"
      ) { res in
        #expect(res.status == .seeOther)
      }
      #expect(stub.sets.first?.request.paidReductionReference == "T-1")
    }
  }

  @Test("service-side refusal shows the warning with the service's figures")
  func serviceRefuses() async throws {
    let stub = StubEntitlements(records: [freeKey])
    stub.setError = .acknowledgmentRequired(
      PaidReductionDetail(
        key: "initiative.connections", paid: .count(7), proposed: .count(1),
        payments: [grant("stripe_purchase", value: .count(7), product: "pack", quantity: 1)]))
    try await withStub(stub) { app in
      try await post(
        app, "users/u1/entitlements/initiative.connections/override", "value=5&reason=perk"
      ) { res in
        let body = res.body.string
        #expect(body.contains("Reducing something this user paid for"))
        #expect(body.contains("<strong>7</strong>"))
        #expect(body.contains("stripe_purchase pack x1: 7"))
      }
    }
  }

  @Test("a service validation error is shown verbatim and nothing changes")
  func serviceValidation() async throws {
    let stub = StubEntitlements(records: [freeKey])
    stub.setError = .validation("value exceeds the key maximum of 10")
    try await withStub(stub) { app in
      try await post(
        app, "users/u1/entitlements/initiative.connections/override", "value=50&reason=perk"
      ) { res in
        #expect(res.status == .unprocessableEntity)
        #expect(res.body.string.contains("value exceeds the key maximum of 10"))
      }
    }
  }

  @Test("remove asks for confirmation and a reason, then removes")
  func removeFlow() async throws {
    let stub = StubEntitlements(records: [paidKey])
    try await withStub(stub) { app in
      let path = "users/u1/entitlements/initiative.theme_slots/remove"
      try await post(app, path, "") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("restores the computed value"))
      }
      #expect(stub.removals.isEmpty)
      try await post(app, path, "confirmed=yes&reason=") { res in
        #expect(res.status == .unprocessableEntity)
      }
      try await post(app, path, "confirmed=yes&reason=done") { res in
        #expect(res.status == .seeOther)
      }
      #expect(stub.removals.first?.reason == "done")
    }
  }
}

@Suite("Payment detail")
struct PaymentDetailTests {
  private func bundleGrant(amount: Int?, at: String?) -> GrantLine {
    GrantLine(
      source: "stripe_purchase", value: .count(5), mode: nil, productId: "pack", quantity: 1,
      reason: nil, setBy: nil, validUntil: nil, purchasedAt: at, firstPurchasedAt: at,
      amount: amount, currency: amount == nil ? nil : "usd")
  }

  @Test("a bundle's repeated charge is shown once, not summed")
  func bundleShownOnce() {
    let grants = [
      bundleGrant(amount: 1250, at: "2026-10-01T12:00:00Z"),
      bundleGrant(amount: 1250, at: "2026-10-01T12:00:00Z"),
    ]
    let charges = EntitlementsPresenter.charges(grants, l10n: [:])
    #expect(charges.count == 1)
    #expect(charges.first?.value == "12.50 USD, 2026-10-01")
  }

  @Test("null amount and date render as not recorded")
  func notRecorded() {
    let charges = EntitlementsPresenter.charges(
      [bundleGrant(amount: nil, at: nil)], l10n: ["entitlements_not_recorded": "not recorded"])
    #expect(charges.first?.value == "not recorded, not recorded")
  }

  @Test("the 409 body decodes payment fields, and old grants without them still decode")
  func decodes() throws {
    let json =
      #"{"source":"stripe_purchase","value":5,"created_at":"x","purchased_at":"2026-10-01T12:00:00Z","amount":1250,"currency":"usd"}"#
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let grant = try decoder.decode(GrantLine.self, from: Data(json.utf8))
    #expect(grant.amount == 1250 && grant.currency == "usd")
    let old = try decoder.decode(
      GrantLine.self, from: Data(#"{"source":"stripe_purchase","value":5}"#.utf8))
    #expect(old.amount == nil && old.purchasedAt == nil)
  }
}

@Suite("Entitlements wiring")
struct EntitlementsWiringTests {
  @Test("the users list links each row to its entitlements page under the path prefix")
  func listLink() async throws {
    try await withApp { app in
      try I18n.loadTables()
      app.views.use(.leaf)
      app.get("test-users") { req async throws -> View in
        let summary = LeafUserSummary(
          subject: "auth0|abc", userID: "u 1", email: "a@example.com", roles: ["user"],
          deniedServices: [])
        return try await req.view.render(
          "users/list",
          UsersListContext(
            users: [summary], isEmpty: false, allRoles: UsersController.allRoles,
            unavailable: false, user: nil, meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-users") { res in
        #expect(res.body.string.contains(#"href="/users/u%201/entitlements""#))
      }
    }
  }

  @Test("startup names the missing ENTITLEMENTS_API_URL")
  func missingSetting() {
    unsetenv("ENTITLEMENTS_API_URL")
    #expect(throws: EntitlementsAPIConfig.MissingSettingError.self) {
      try EntitlementsAPIConfig.fromEnvironment()
    }
  }

  @Test("every localization key the templates and controller use exists")
  func localizationKeysExist() throws {
    try I18n.loadTables()
    let table = try #require(I18n.tables["en"])
    let views = ["users/entitlements.leaf", "users/entitlements-confirm.leaf"]
    let pattern = try NSRegularExpression(pattern: #"meta\.l10n\.([A-Za-z0-9_]+)"#)
    var used = Set<String>()
    for view in views {
      let text = try String(contentsOfFile: "Resources/Views/\(view)", encoding: .utf8)
      let range = NSRange(text.startIndex..., in: text)
      for match in pattern.matches(in: text, range: range) {
        used.insert(String(text[Range(match.range(at: 1), in: text)!]))
      }
    }
    let controller = try String(
      contentsOfFile: "Sources/App/Controllers/UserEntitlementsController.swift", encoding: .utf8)
    let quoted = try NSRegularExpression(pattern: #"l10n\["([a-z0-9_]+)"\]"#)
    for match in quoted.matches(
      in: controller, range: NSRange(controller.startIndex..., in: controller))
    {
      used.insert(String(controller[Range(match.range(at: 1), in: controller)!]))
    }
    used.formUnion(["entitlements_flag_on", "entitlements_flag_off"])
    let missing = used.filter { table[$0] == nil }
    #expect(missing.isEmpty, "missing keys: \(missing.sorted())")
  }

  @Test("the client maps the service's paid-reduction 409 and other errors")
  func clientErrorMapping() {
    func response(_ status: HTTPStatus, _ json: String) -> ClientResponse {
      ClientResponse(
        status: status, headers: ["Content-Type": "application/json"],
        body: ByteBuffer(string: json))
    }
    let conflict = response(
      .conflict,
      #"{"error":"paid_reduction_not_acknowledged","message":"m","key":"k","paid":10,"proposed":3,"payments":[{"source":"stripe_purchase","value":5,"quantity":1}]}"#
    )
    guard case .acknowledgmentRequired(let detail) = EntitlementsAPIClient.error(for: conflict)
    else {
      Issue.record("expected acknowledgmentRequired")
      return
    }
    #expect(detail.paid == .count(10) && detail.proposed == .count(3))
    #expect(detail.payments.count == 1)
    #expect(EntitlementsAPIClient.error(for: response(.unauthorized, "{}")) == .unauthorized)
    #expect(EntitlementsAPIClient.error(for: response(.notFound, "{}")) == .notFound)
    #expect(
      EntitlementsAPIClient.error(
        for: response(.badRequest, #"{"error":"invalid_request","message":"bad"}"#))
        == .validation("bad"))
    #expect(
      EntitlementsAPIClient.error(
        for: response(.forbidden, #"{"error":"paid_reductions_disabled","message":"off"}"#))
        == .paidReductionsDisabled)
    #expect(EntitlementsAPIClient.error(for: response(.internalServerError, "{}")) == .unavailable)
  }
}
