import Fluent

struct CreateUserDevice: AsyncMigration {
    func prepare(on database: Database) async throws {
        let env = try await database.enum("env")
            .case("dev")
            .case("test")
            .case("live")
            .create()
        
        try await database.schema(UserDevice.schema)
            .field("id", .string, .identifier(auto: false))
            .field("user_token", .string)
            .field("env", env, .required)
            .field("user_id", .string, .references(User.schema, "id"), .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.enum("env").delete()
        try await database.schema(UserDevice.schema).delete()
    }
}
