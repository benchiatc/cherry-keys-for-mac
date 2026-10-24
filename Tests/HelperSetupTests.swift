import Foundation
import ServiceManagement

@main
struct HelperSetupTests {
    static func main() {
        var checks = 0
        func check(_ result: HelperSetupResult, _ expected: HelperSetupResult, _ message: String) {
            precondition(result == expected, message)
            checks += 1
        }
        let authorization = NSError(
            domain: "SMAppServiceErrorDomain", code: Int(kSMErrorLaunchDeniedByUser))
        let failure = NSError(
            domain: "SMAppServiceErrorDomain", code: Int(kSMErrorInvalidSignature),
            userInfo: [NSLocalizedDescriptionKey: "Invalid signature"])
        check(
            .resolve(status: .notRegistered, returned: false, error: nil, elapsed: 0), .registering,
            "Registration in flight must not report a failure")
        check(
            .resolve(status: .requiresApproval, returned: true, error: authorization, elapsed: 30),
            .awaitingApproval, "Approval-required exception must remain pending")
        check(
            .resolve(status: .notRegistered, returned: true, error: authorization, elapsed: 30),
            .awaitingApproval, "Authorization may precede status propagation")
        check(
            .resolve(status: .enabled, returned: true, error: authorization, elapsed: 31), .ready,
            "Later approval supersedes the earlier exception")
        check(
            .resolve(status: .enabled, returned: false, error: nil, elapsed: 0), .ready,
            "Live enabled status wins even before register returns")
        check(
            .resolve(status: .requiresApproval, returned: true, error: nil, elapsed: 60),
            .awaitingApproval, "An unapproved service remains actionable without a modal")
        check(
            .resolve(status: .notRegistered, returned: true, error: failure, elapsed: 0),
            .registering, "An exception waits for status propagation")
        check(
            .resolve(status: .notRegistered, returned: true, error: failure, elapsed: 2),
            .failed("Invalid signature"), "Persistent genuine failures remain visible")
        check(
            .resolve(status: .notFound, returned: true, error: failure, elapsed: 3),
            .failed("Invalid signature"), "A missing or invalid helper must not be masked")
        let unrelated = NSError(
            domain: "OtherDomain", code: Int(kSMErrorLaunchDeniedByUser),
            userInfo: [NSLocalizedDescriptionKey: "Other failure"])
        check(
            .resolve(status: .notRegistered, returned: true, error: unrelated, elapsed: 3),
            .failed("Other failure"), "An unrelated error with the same number is not authorization"
        )
        print(
            "PASS: \(checks) helper-setup transition regression checks. No service registrations or permission changes."
        )
    }
}
