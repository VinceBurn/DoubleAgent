//
//  File.swift
//
//
//  Created by Vincent Bernier on 2021-02-23.
//

import Codability
import Fluent
import FluentSQLiteDriver
import Vapor

func sanitized(path: String) -> String { path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
func resolve(path: String, mapping: [String: String]?) -> String
{
    guard let mapping = mapping else { return path }
    return path
        .pathComponents
        .map
        {
            switch $0
            {
            case .parameter:
                if let mapped = mapping[$0.description].map({ PathComponent.constant($0) }) { return mapped }
                else { return $0 }
            default:
                return $0
            }
        }
        .string
}

public struct ConflictError: Error, Content
{
    public struct CallInfoSummary: Content
    {
        let callInfoID: UUID?
        let path: String
        let method: HTTPMethod
        let lookup: CallLookup?

        init(_ info: DB.CallInfo)
        {
            callInfoID = info.id
            path = info.path
            method = info.method
            lookup = info.lookup
        }
    }

    public struct RequestSummary: Content
    {
        let method: HTTPMethod
        let url: String
        let headers: HTTPHeaders

        init(_ request: Request)
        {
            method = request.method
            url = sanitized(path: request.url.string)
            headers = request.headers
        }
    }

    let error = true
    let reason: String
    let requestToMatch: RequestSummary
    let conflictingMatches: [CallInfoSummary]

    enum CodingKeys: CodingKey
    {
        case error, reason, requestToMatch, conflictingMatches
    }
}

public struct CallInfo: Content
{
    var id: UUID?
    var createdAt: Date?

    var path: String
    var method: HTTPMethod
    var lookup: CallLookup?

    var response: CallResponse?

    init(
        id: UUID? = nil,
        createdAt: Date? = nil,
        path: String,
        method: HTTPMethod,
        lookup: CallLookup?,
        response: CallResponse?
    )
    {
        self.id = id
        self.createdAt = createdAt
        self.path = path
        self.method = method
        self.lookup = lookup
        self.response = response
    }

    init(_ callInfo: DB.CallInfo)
    {
        id = callInfo.id
        createdAt = callInfo.createdAt
        path = callInfo.path
        method = callInfo.method
        lookup = callInfo.lookup
        if callInfo.$responses.value != nil,
           let response = callInfo.responses.first
        {
            self.response = CallResponse(response)
        }
        else { response = nil }
    }
}

public struct CallLookup: Content, Equatable
{
    var path: [String: String]?
    var query: [String: String]?
    var headers: HTTPHeaders?
    var body: String?

    var weight: Int { (query?.count ?? 0) + (headers?.count ?? 0) + (body == nil ? 0 : 9999) }

    init(path: [String: String]?, query: [String: String]?, headers: HTTPHeaders?, body: String?)
    {
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }
}

public struct CallResponse: Content
{
    var id: UUID?
    var status: HTTPStatus?
    var headers: HTTPHeaders?
    var body: AnyCodable?

    init(id: UUID? = nil, status: HTTPStatus? = nil, headers: HTTPHeaders? = nil, body: AnyCodable? = nil)
    {
        self.id = id
        self.status = status
        self.headers = headers
        self.body = body
    }

    init(_ response: DB.MockResponse)
    {
        id = response.id
        body = response.body
        headers = response.headers
        if let status = response.status
        {
            self.status = HTTPResponseStatus(statusCode: status.code, reasonPhrase: status.reasonPhrase)
        }
    }
}

enum DB {}

extension DB
{
    final class CallInfo: Model
    {
        static var schema: String = "MockCallInfo"

        @ID(key: .id)
        var id: UUID?

        @Timestamp(key: "created_at", on: .create, format: .iso8601)
        var createdAt: Date?

        @Field(key: "path")
        var path: String

        @Field(key: "sanitized_path")
        var sanitizedPath: String

        @Field(key: "path_count")
        var pathCount: Int

        @Enum(key: "method")
        var method: HTTPMethod

        @OptionalField(key: "lookup") // TODO: Could we use a Group
        var lookup: CallLookup?

        @Children(for: \.$callInfo)
        var responses: [DB.MockResponse]

        init() {}

        init(_ callInfo: App.CallInfo)
        {
            id = callInfo.id
            createdAt = callInfo.createdAt
            path = resolve(path: callInfo.path, mapping: callInfo.lookup?.path)
            sanitizedPath = sanitized(path: path)
            pathCount = sanitizedPath.components(separatedBy: "/").count
            method = callInfo.method
            lookup = callInfo.lookup
        }
    }

    final class MockStatus: Content
    {
        var code: Int
        var reasonPhrase: String

        init?(code: UInt?, reasonPhrase: String?)
        {
            guard let code = code, let reasonPhrase = reasonPhrase else { return nil }

            self.code = Int(code)
            self.reasonPhrase = reasonPhrase
        }
    }

    final class MockResponse: Model
    {
        static var schema: String = "MockResponse"

        @ID(key: .id)
        var id: UUID?

        @OptionalField(key: "status")
        var status: DB.MockStatus?

        @OptionalField(key: "headers")
        var headers: HTTPHeaders?

        @OptionalField(key: "body")
        var body: AnyCodable?

        @Parent(key: "call_info")
        var callInfo: DB.CallInfo

        init() {}

        init(_ callResponse: App.CallResponse)
        {
            id = callResponse.id
            headers = callResponse.headers
            status = MockStatus(code: callResponse.status?.code, reasonPhrase: callResponse.status?.reasonPhrase)
            body = callResponse.body
        }
    }
}

extension DB.MockResponse: Content {}

extension DB.MockResponse: Migration
{
    func prepare(on database: Database) -> EventLoopFuture<Void>
    {
        return database
            .schema(DB.MockResponse.schema)
            .id()
            .field("status", .json)
            .field("headers", .json)
            .field("body", .data)
            .field("call_info", .uuid, .required, .references(DB.CallInfo.schema, "id"))
            .foreignKey("call_info", references: DB.CallInfo.schema, "id", onDelete: .cascade)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void>
    {
        return database.schema(DB.MockResponse.schema).delete()
    }
}

extension DB.CallInfo: Content {}

extension DB.CallInfo: Migration
{
    func prepare(on database: Database) -> EventLoopFuture<Void>
    {
        return database
            .schema(DB.CallInfo.schema)
            .id()
            .field("created_at", .datetime, .required)
            .field("path", .string, .required)
            .field("sanitized_path", .string, .required)
            .field("path_count", .int, .required)
            .field("method", .string, .required)
            .field("lookup", .json)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void>
    {
        return database.schema(DB.CallInfo.schema).delete()
    }
}

extension HTTPMethod: Codable
{
    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(from decoder: Decoder) throws
    {
        let container = try decoder.singleValueContainer()
        let val = try container.decode(String.self).uppercased()
        self.init(rawValue: val)
    }
}
