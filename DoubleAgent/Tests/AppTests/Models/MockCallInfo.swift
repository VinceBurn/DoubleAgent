//
//  File.swift
//
//
//  Created by Vincent Bernier on 2021-02-26.
//

@testable import App
import Codability
import XCTVapor

extension CallInfo
{
    static func stub(
        id: UUID? = nil,
        path: String = "r",
        method: HTTPMethod = .GET,
        lookup: CallLookup? = nil,
        response: CallResponse? = nil
    ) -> CallInfo
    {
        return CallInfo(
            id: id,
            path: path,
            method: method,
            lookup: lookup,
            response: response
        )
    }

    var responseBodyBuffer: ByteBuffer? { try? Response.Body(data: JSONEncoder().encode(self)).buffer }
    var jsonData: Data? { try? JSONEncoder().encode(self) }
}

extension CallInfo: Equatable
{
    public static func == (lhs: CallInfo, rhs: CallInfo) -> Bool
    {
        return lhs.id == rhs.id &&
//            lhs.createdAt == rhs.createdAt && cannot set this manually
            lhs.path == rhs.path &&
            lhs.method == rhs.method
    }
}

extension CallLookup
{
    static func stub(
        path: [String: String]? = nil,
        query: [String: String]? = nil,
        headers: HTTPHeaders? = nil,
        body: String? = nil
    ) -> CallLookup
    {
        return CallLookup(path: path, query: query, headers: headers, body: body)
    }
}

extension CallResponse
{
    static func stub(
        id: UUID? = nil,
        status: HTTPStatus? = nil,
        headers: HTTPHeaders? = nil,
        body: AnyCodable? = nil
    ) -> CallResponse
    {
        return CallResponse(
            id: id,
            status: status,
            headers: headers,
            body: body
        )
    }
}
