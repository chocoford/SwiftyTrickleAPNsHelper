import Fluent

struct CreateUserWorkspace: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("user_workspaces")
            .id()
            .field("workspace_id", .string, .required)
            .field("member_id", .string, .required)
            .field("user_id", .uuid, .references("users", "id"))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_workspaces").delete()
    }
}
