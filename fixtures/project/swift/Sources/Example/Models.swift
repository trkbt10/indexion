import Foundation

/// A user in the system.
public struct User {
    public let name: String
    public let age: Int

    public init(name: String, age: Int) {
        self.name = name
        self.age = age
    }

    /// Returns a formatted display name.
    public func displayName() -> String {
        return "\(name) (age \(age))"
    }
}

/// Validates entities.
public protocol Validator {
    func validate(_ input: Any) -> Bool
}

/// An internal helper.
internal class InternalHelper {
    private func doSomething() {}
}
