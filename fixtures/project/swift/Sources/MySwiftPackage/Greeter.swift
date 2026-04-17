import Foundation
import Logging

/// Produces localized greeting strings for users.
public struct Greeter {
    private let logger: Logger

    public init(logger: Logger = Logger(label: "MySwiftPackage.Greeter")) {
        self.logger = logger
    }

    /// Returns a greeting message for the given user.
    public func greet(_ user: User) -> String {
        logger.debug("greeting user \(user.name)")
        return "Hello, \(user.displayName())!"
    }
}
