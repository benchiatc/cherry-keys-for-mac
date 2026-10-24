import Foundation
import ServiceManagement

enum HelperSetupResult: Equatable {
    case registering, awaitingApproval, ready
    case failed(String)

    static func resolve(
        status: SMAppService.Status, returned: Bool,
        error: NSError?, elapsed: TimeInterval
    ) -> Self {
        // The live service status takes precedence over the register() result.
        // macOS can return an authorization error while its approval UI opens.
        if status == .enabled { return .ready }
        if status == .requiresApproval { return .awaitingApproval }
        guard returned else { return .registering }
        if let error, error.domain == "SMAppServiceErrorDomain",
            [
                Int(EPERM), Int(kSMErrorAuthorizationFailure), Int(kSMErrorJobMustBeEnabled),
                Int(kSMErrorLaunchDeniedByUser),
            ].contains(error.code)
        {
            return .awaitingApproval
        }
        // Allow asynchronous Service Management status propagation before
        // presenting a genuine registration/package failure.
        guard elapsed >= 2 else { return .registering }
        return .failed(
            error?.localizedDescription
                ?? "Helper registration is not enabled. Check Login Items & Extensions, then retry setup."
        )
    }
}
