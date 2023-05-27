import NIOSSL
import Fluent
import FluentSQLiteDriver
import Vapor
import APNS


// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // Configure APNS using JWT authentication.
    app.apns.configuration = try .init(
        authenticationMethod: .jwt(
            key: .private(pem: ProcessInfo.processInfo.environment["APNS_PEM"] ?? ""),
            keyIdentifier: .init(string: ProcessInfo.processInfo.environment["APNS_KEY_ID"] ?? ""),
            teamIdentifier: "96RJ77RT4T"
        ),
        topic: "com.chocoford.SwiftyTrickle-Debug",
        environment: .sandbox
    )
    
    app.databases.use(.sqlite(.memory), as: .sqlite)

    app.migrations.add(CreateTodo())
    app.migrations.add(CreateUser())
    app.migrations.add(CreateUserWorkspace())
    
    // register routes
    try routes(app)
}
