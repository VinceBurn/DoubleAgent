import Fluent
import FluentSQLiteDriver
import Vapor

// configures your application
public func configure(_ app: Application) throws
{
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

//    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    let sqliteConf: SQLiteConfiguration = app.environment.name == Environment.testing.name ? .memory : .memory
    app.databases.use(.sqlite(sqliteConf), as: .sqlite)

    app.migrations.add(DB.MockResponse())
    app.migrations.add(DB.CallInfo())

    app.logger.logLevel = .debug
    try app.autoMigrate().wait()

    // register routes
    app.routes.defaultMaxBodySize = "5mb"
    try routes(app)
}
