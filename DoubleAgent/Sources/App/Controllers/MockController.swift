//
//  File.swift
//
//
//  Created by Vincent Bernier on 2021-02-23.
//

import Codability
import Fluent
import Vapor

extension PathComponent
{
    var isCatchAll: Bool
    {
        if case PathComponent.catchall = self { return true }
        else { return false }
    }
}

final class MockController
{
    func help(_ request: Request) throws -> String
    {
        return "TODO: Make Instruction"
    }

    func allResponses(_ request: Request) throws -> EventLoopFuture<[CallInfo]>
    {
        return try allDBResponses(request).mapEach(CallInfo.init)
    }

    func allDBResponses(_ request: Request) throws -> EventLoopFuture<[DB.CallInfo]>
    {
        return DB.CallInfo
            .query(on: request.db)
            .with(\.$responses)
            .all()
    }

    func create(_ request: Request) throws -> EventLoopFuture<HTTPResponseStatus>
    {
        let callInfo = try request.content.decode(CallInfo.self)
        if callInfo.path.pathComponents.contains(where: { $0.isCatchAll })
        {
            throw Abort(
                .preconditionFailed,
                reason: "** is not a valid wildcard. Use * or :paramName instead"
            )
            // TODO: Other validation, like path substitution all map to something in the path
        }
        let content = DB.CallInfo(callInfo)
        if let r = callInfo.response
        {
            let response = DB.MockResponse(r)
            return content
                .save(on: request.db)
                .flatMap { content.$responses.create(response, on: request.db) }
                .transform(to: .ok)
        }

        return content
            .save(on: request.db)
            .transform(to: .ok)
    }

    func resetAll(_ request: Request) throws -> EventLoopFuture<HTTPResponseStatus>
    {
        return DB.CallInfo.query(on: request.db)
            .with(\.$responses)
            .all()
            .sequencedFlatMapEach
            { response -> EventLoopFuture<Void> in
                return response.delete(on: request.db)
            }
            .transform(to: HTTPStatus.ok)
    }

    func lookup(_ request: Request) throws -> EventLoopFuture<Response>
    {
        let sanitizedPath = sanitized(path: request.url.path)
        return DB.CallInfo.query(on: request.db)
            .filter(\.$pathCount == sanitizedPath.components(separatedBy: "/").count)
            .filter(\.$method == request.method)
            .all()
            .flatMapThrowing({ calls -> UUID in
                let inputPaths = sanitizedPath.pathComponents
                var matches = calls
                    .filter { self.isPath(inputPaths, matching: $0.sanitizedPath.pathComponents) }
                    .filter { self.isQuery(request.query, matching: $0.lookup?.query) }
                    .filter { self.isHeaders(request.headers, matching: $0.lookup?.headers) }
                    .filter { self.isBody(request, matching: $0.lookup?.body) }
                let exactMatches = matches.filter { $0.sanitizedPath == sanitizedPath }
                if !exactMatches.isEmpty { matches = exactMatches }
                let maxCount = matches.reduce(0) { acc, call in max(acc, call.lookup?.weight ?? 0) }
                matches = matches.filter { ($0.lookup?.weight ?? 0) == maxCount }

                if matches.isEmpty { throw Abort(.notFound) }
                // TODO: Revisit the return value, maybe send ids or resolution info, for resolution debugging purposes
                else if matches.count > 1 { throw Abort(.conflict, reason: "Multiple Response Matches") }

                guard let id = matches[0].id else { throw Abort(.notFound) }
                return id
            })
            .flatMap
            { id -> EventLoopFuture<DB.CallInfo> in
                return DB.CallInfo.query(on: request.db)
                    .filter(\.$id == id)
                    .with(\.$responses)
                    .first()
                    .unwrap(or: Abort(.notFound))
            }
            .map { return CallInfo($0) }
            .flatMapThrowing
            { (callInfo: CallInfo) -> Response in
                let savedBody: AnyCodable = callInfo.response?.body ?? ""
                var buffer = ByteBuffer()
                var headers: HTTPHeaders = ["mocked-call-id": callInfo.id?.uuidString ?? "no-id"]
                let encoder = try ContentConfiguration.default().requireEncoder(for: savedBody.mediaType)
                try encoder.encode(savedBody, to: &buffer, headers: &headers)
                // TODO: Test le `empty`
                let body = callInfo.response?.body != nil ? Response.Body(buffer: buffer) : .empty
                return Response(
                    status: callInfo.response?.status ?? .ok,
                    version: .http1_1,
                    headers: headers.replaceOrAdd(callInfo.response?.headers),
                    body: body
                )
            }
            .flatMap { request.eventLoop.makeSucceededFuture($0) }
    }

    private func isPath(_ path: [PathComponent], matching possible: [PathComponent]) -> Bool
    {
        guard path.count == possible.count, !path.isEmpty else { return false }
        return zip(possible, path)
            .reduce(true)
            { acc, t in
                guard acc == true else { return false }
                switch t
                {
                case (.anything, _), (.parameter, _):
                    return true
                case let (.constant(l), .constant(r)):
                    return l.lowercased() == r.lowercased()
                default:
                    return false
                }
            }
    }

    private func isQuery(_ query: URLQueryContainer, matching requirements: [String: String]?) -> Bool
    {
        guard let requirements = requirements else { return true }
        return requirements.reduce(true, { acc, i in
            guard
                acc,
                let expectedValue = query[String.self, at: i.key]?.removingPercentEncoding
            else { return false }
            return expectedValue == (i.value.removingPercentEncoding ?? i.value)
        })
    }

    private func isHeaders(_ headers: HTTPHeaders, matching requirements: HTTPHeaders?) -> Bool
    {
        guard let requirements = requirements else { return true }
        return requirements.reduce(true)
        { (acc, header) -> Bool in
            guard acc else { return false }

            let expectedValue = headers[header.name]
            return expectedValue.contains(header.value)
        }
    }

    private func isBody(_ request: Request?, matching requirements: String?) -> Bool
    {
        guard let bodyString = request?.body.string,
              let requirements = requirements
        else { return true }

        if let bodyData = bodyString.data(using: .utf8),
           let reqData = requirements.data(using: .utf8),
           let body = try? JSONSerialization.jsonObject(with: bodyData, options: []) as? NSObject,
           let req = try? JSONSerialization.jsonObject(with: reqData, options: []) as? NSObject
        {
            // AnyCodable equality don't play well with JSON objects
            return body.isEqual(req)
        }
        else { return bodyString == requirements }
    }
}

extension HTTPHeaders
{
    @discardableResult
    mutating func replaceOrAdd(_ headers: HTTPHeaders?) -> HTTPHeaders
    {
        guard let headers = headers else { return self }
        headers.forEach { replaceOrAdd(name: $0.name, value: $0.value) }
        return self
    }
}

extension AnyCodable
{
    var mediaType: HTTPMediaType
    {
        if value is [AnyHashable: Any] ||
            value is [Any]
        { return .json }
        else { return .plainText }
    }

    var contentType: String { mediaType.serialize() }
}

extension MockController: RouteCollection
{
    /// Setup the routes
    func boot(routes: RoutesBuilder) throws
    {
        let mocks = routes.grouped("mocks")
        mocks.get(use: allResponses)
        mocks.get("db", use: allDBResponses) // For Debug purposes, not unit tested
        mocks.post(use: create)
        mocks.delete("resetAll", use: resetAll)
        mocks.get("help", use: help)

        routes.get(.catchall, use: lookup)
        routes.post(.catchall, use: lookup)
        routes.put(.catchall, use: lookup)
        routes.delete(.catchall, use: lookup)
        routes.patch(.catchall, use: lookup)
    }
}
