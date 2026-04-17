import ArgumentParser
import MySwiftPackage

@main
struct CLI: ParsableCommand {
    @Argument var name: String

    mutating func run() throws {
        let user = User(name: name, age: 0)
        print(Greeter().greet(user))
    }
}
