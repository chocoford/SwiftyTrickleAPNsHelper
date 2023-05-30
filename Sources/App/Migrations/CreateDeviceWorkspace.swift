import Fluent

struct CreateDeviceWorkspace: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(DeviceWorkspace.schema)
            .id()
            .field("workspace_id", .string, .required)
            .field("member_id", .string, .required)
            .field("device_token", .string, .references(UserDevice.schema, "id"))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(DeviceWorkspace.schema).delete()
    }
}
