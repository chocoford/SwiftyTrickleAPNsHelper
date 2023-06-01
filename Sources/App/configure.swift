import NIOSSL
import Fluent
import FluentSQLiteDriver
import Vapor
import APNS
import Jobs


// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    print(ProcessInfo.processInfo.environment["APNS_PEM"]?.replacingOccurrences(of: "\\n", with: "\n") ?? "no APNS_PEM")
    
    // Configure APNS using JWT authentication.
    app.apns.configuration = try .init(
        authenticationMethod: .jwt(
            key: .private(pem: ProcessInfo.processInfo.environment["APNS_PEM"]?.replacingOccurrences(of: "\\n", with: "\n") ?? ""),
            keyIdentifier: .init(string: ProcessInfo.processInfo.environment["APNS_KEY_ID"] ?? ""),
            teamIdentifier: "96RJ77RT4T"
        ),
        topic: ProcessInfo.processInfo.environment["APNS_TOPIC"] ?? "com.chocoford.SwiftyTrickle",
        environment: ProcessInfo.processInfo.environment["APNS_ENV"] == "production" ? .production : .sandbox
    )
    
    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

    app.migrations.add(CreateUser())
    app.migrations.add(CreateUserDevice())
    app.migrations.add(CreateDeviceWorkspace())
    
    // register routes
    try routes(app)
    
    Jobs.oneoff(delay: 3.seconds) {
        Task {
            _ = try? await app.client.post("http://127.0.0.1/users/register_all")
        }
    }
    
}
