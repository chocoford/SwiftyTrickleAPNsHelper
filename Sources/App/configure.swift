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
            key: .private(pem: """
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgtJE6FyzaK4G+qdjN
hS4o65GqrIk+47uU7l9rSl/hXZqhRANCAASnfEkUTKz4T2hnXDs3n5Sp7hXM1GJe
RmPaSZxwPsYoRoIIY2hpQhOn/VbgAv/B3K92Or+BPpO2elo3jIH9MJ1E
-----END PRIVATE KEY-----
"""),
            keyIdentifier: "BHPU8XMU7C",
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
