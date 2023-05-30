import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req async in
//        print(req.headers.description, req.remoteAddress?.hostname)
        return "It works!"
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    try app.register(collection: TodoController())
    try app.register(collection: UserController())
}
