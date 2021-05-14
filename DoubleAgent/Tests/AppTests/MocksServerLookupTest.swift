//
//  File.swift
//
//
//  Created by Vincent Bernier on 2021-02-28.
//

@testable import App
import Codability
import XCTVapor

// deal with basiAuth header ??
// improve not found error to include request information

extension Data
{
    var byteBuffer: ByteBuffer { ByteBuffer(data: self) }
}

final class MocksServerLookupTest: MocksServerTestCase
{
    struct JSONBodies: Codable
    {
        let bodies: [JSONBody]
        init(bodies: [JSONBody]) { self.bodies = bodies }
    }

    struct JSONBody: Codable
    {
        let id: String?
        let isSomething: Bool?
        let items: [String]

        init(
            id: String? = nil,
            isSomething: Bool? = nil,
            items: [String] = ["1", "2", "3"]
        )
        {
            self.id = id
            self.isSomething = isSomething
            self.items = items
        }
    }

    func assertCall(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: Data? = nil,
        response responseBody: String,
        message: String = "",
        function: String = #function
    ) throws
    {
        try app.test(method, path, headers: headers, body: body?.byteBuffer)
        { response in
            XCTAssertEqual(response.body.string, responseBody, "\(message) :: test -> \(function)")
        }
    }

    func assertErrorNotFound(
        _ method: HTTPMethod,
        _ path: String,
        body: Data? = nil,
        message: String = "",
        function: String = #function
    ) throws
    {
        try app.test(method, path, body: body?.byteBuffer) { XCTAssertEqual($0.status, .notFound, "\(message) :: test -> \(function)") }
    }

    func assertErrorConflict(
        _ method: HTTPMethod,
        _ path: String,
        body: Data? = nil,
        headers: HTTPHeaders = [:],
        message: String = "",
        function: String = #function
    ) throws
    {
        try app.test(method, path, headers: headers, body: body?.byteBuffer)
        {
            try assertBaseMultipleMatchError(in: $0, function: function)
        }
    }

    func assertBaseMultipleMatchError(in response: XCTHTTPResponse, function: String = #function) throws
    {
        let data = Data(buffer: response.body)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let errorDic = try XCTUnwrap(jsonObject as? NSDictionary)
        print(response.headers)
        XCTAssertEqual(response.content.contentType, .json, "Error has JSON content")
        XCTAssertEqual(response.status, .conflict, "Multiple Match result in `conflict` status [\(function)]")
        XCTAssertEqual(errorDic["error"] as? Bool, true, "response body has field: error == true [\(function)]")
        XCTAssertEqual(errorDic["reason"] as? String, "Found Multiple Responses Matches", "response body has specific reason message [\(function)]")
    }

    // MARK: - Matching on Path
    func test_givenDynamicPath_whenPathToShort_thenNotFound() throws
    {
        try registerMocks(CallInfo.stub(path: "some/:id", method: .GET))
        try registerMocks(CallInfo.stub(path: "other/*", method: .GET))
        try assertErrorNotFound(.GET, "some", message: "Dynamic path needs to be present / have a value")
        try assertErrorNotFound(.GET, "other", message: "Dynamic path needs to be present / have a value")
    }

    func test_givenDynamicPath_whenLookup_thenMatchOnAllNonDynamicPath() throws
    {
        try registerMocks(CallInfo.stub(path: "some/:id/dynamic", method: .GET, response: CallResponse.stub(body: "dynamic")))
        try registerMocks(CallInfo.stub(path: "some/*/all", method: .GET, response: CallResponse.stub(body: "all")))
        try assertCall(.GET, "some/1234/dynamic", response: "dynamic", message: ":name can be use as a wildcard")
        try assertCall(.GET, "some/v_134_df/all", response: "all", message: "* can be use as a wildcard")
    }

    func test_givenDynamicAndStaticPath_whenBothMatch_theReturnStatic() throws
    {
        try registerMocks(CallInfo.stub(path: "some/*/all", method: .GET, response: CallResponse.stub(body: "not")))
        try registerMocks(CallInfo.stub(path: "some/123/all", method: .GET, response: CallResponse.stub(body: "good")))
        try assertCall(.GET, "some/123/all", response: "good", message: "Fully defined path has precedence over wildcard")
    }

    func test_givenCatchAllInPath_whenCreation_thenError() throws
    {
        try registerMocks(CallInfo.stub(path: "some/**/stuff"), afterResponse: { response in
            XCTAssert(response.status != .ok)
            XCTAssertEqual(response.status, .preconditionFailed)
            XCTAssertTrue(response.body.string.contains("** is not a valid wildcard. Use * or :paramName instead"))
        })
    }

    func test_givenPathSubstitution_willMatchOnlyForSubstitution() throws
    {
        try registerMocks(.stub(path: "bob/:id", method: .GET, lookup: .stub(path: [":id": "123"]), response: .stub(body: "good")))
        try assertErrorNotFound(.GET, "bob/no", message: "Dynamic path with replacement is not a wildcard")
        try assertCall(.GET, "bob/123", response: "good", message: "Only match with lookup value")
    }

    func test_givenPathWildcard_whenMultipleMatch_thenError() throws
    {
        try registerMocks([.stub(path: "a/*/c"), .stub(path: "a/b/*")])
        try assertErrorConflict(.GET, "a/b/c", message: "Multiple wild card path match is a conflict error")
    }

    // MARK: - Matching on Query
    func test_givenOnlyPath_whenQuery_thenMatch() throws
    {
        try registerMocks(.stub(path: "bob", method: .GET, response: .stub(body: "good")))
        try assertCall(.GET, "bob?bob=true&if=boris", response: "good", message: "Query only matters with substitution")
    }

    func test_givenPathAndQuery_thenMatchOnBoth() throws
    {
        let baseCall = CallInfo.stub(path: "same/path", method: .GET)
        var withoutQuery = baseCall
        withoutQuery.response = .stub(body: "without")
        var with1Query = baseCall
        with1Query.lookup = .stub(query: ["id": "1"])
        with1Query.response = .stub(body: "1 query")
        var with2Query = baseCall
        with2Query.lookup = .stub(query: ["id": "12", "bob": "true"])
        with2Query.response = .stub(body: "2 query")
        var with3Query = baseCall
        with3Query.lookup = .stub(query: ["id": "12", "bob": "true", "p": "1"])
        with3Query.response = .stub(body: "3 query")

        try registerMocks([withoutQuery, with1Query, with2Query, with3Query])
        try assertCall(.GET, "same/path?id=2", response: "without", message: "Query don't match")
        try assertCall(.GET, "same/path?id=12", response: "without", message: "Lookup have 2 query item, finding only one is not a match")
        try assertCall(.GET, "same/path?bob=true", response: "without", message: "Lookup have 2 query item, finding only one is not a match")
        try assertCall(.GET, "same/path?id=1", response: "1 query", message: "The full 1 query item do match")
        try assertCall(.GET, "same/path?id=12&bob=true", response: "2 query", message: "The full 2 query item do match")
        try assertCall(.GET, "same/path?p=1&id=12&bob=true", response: "3 query", message: "2 and 3 query match, the one with more replacement wins")
        try assertCall(.GET, "same/path?id=1&p=1&bob=true&x=false", response: "1 query", message: "Extra query items that don't match are ignore for resolution")
        try assertErrorNotFound(.GET, "other/path?id=1", message: "Query are not considered if the path don't match")
    }

    func test_givenEscapedCharacterInQuery_thenMatchWithNonEscapedVersion() throws
    {
        let call = CallInfo.stub(lookup: .stub(query: ["esc": "+@ %41%42"]), response: .stub(body: "ok"))
        try registerMocks(call)
        try assertCall(call.method, "\(call.path)?esc=%2B%40%20AB", response: "ok")
    }

    func test_exactVsWildCardPath_whenQuery() throws
    {
        let exact = CallInfo.stub(path: "a/b/c", response: .stub(body: "exact"))
        let sub = CallInfo.stub(path: "a/:id/c", lookup: .stub(path: [":id": "c"]), response: .stub(body: "sub"))
        let wild = CallInfo.stub(path: "a/*/c", lookup: .stub(query: ["r2": "d2"]), response: .stub(body: "wild"))
        try registerMocks([wild, exact, sub])
        try assertCall(exact.method, "a/b/c?r2=d2", response: "exact", message: "Exact path match wins over path wild card *")
        try assertCall(exact.method, "a/c/c?r2=d2", response: "sub", message: "Path substitution act like exact path")
        try assertCall(exact.method, "a/x/c?r2=d2", response: "wild", message: "No exact path, the wild card can win")
    }

    func test_givenMultipleQuery_whenOnlyWildCardPath() throws
    {
        let quey1 = CallInfo.stub(path: "a/*/c", lookup: .stub(query: ["1": "a"]), response: .stub(body: "1q"))
        let quey2 = CallInfo.stub(path: "a/*/c", lookup: .stub(query: ["1": "a", "2": "b"]), response: .stub(body: "2q"))

        try registerMocks([quey1, quey2])
        try assertCall(quey1.method, "a/b/c?1=a", response: "1q", message: "")
        try assertCall(quey1.method, "a/b/c?1=a&2=b", response: "2q", message: "")
    }

    func test_givenQueryMatches_when2DifferentMatchOnEqualSizeQuery_thenError() throws
    {
        let call1 = CallInfo.stub(path: "b", lookup: .stub(query: ["a": "1"]))
        let call2 = CallInfo.stub(path: "b", lookup: .stub(query: ["c": "3"]))
        try registerMocks([call1, call2])
        try assertErrorConflict(call1.method, "b?a=1&c=3", message: "Multiple match is a conflict error")
    }

    // MARK: - Matching on Headers
    func test_givenOnlyPath_whenHeaders_thenMatch() throws
    {
        try registerMocks(CallInfo.stub(path: "path/to/there", method: .GET, response: .stub(body: "ok")))
        try assertCall(.GET, "path/to/there", headers: ["header": "value"], response: "ok", message: "Headers only matters when in lookup")
    }

    func test_givenPathAndHeaders_thenMatchOnBoth() throws
    {
        let path = "same/path"
        let baseCall = CallInfo.stub(path: path, method: .PUT)
        var withoutHeaders = baseCall
        withoutHeaders.response = .stub(body: "without")
        var with1Header = baseCall
        with1Header.lookup = .stub(path: nil, query: nil, headers: ["h": "2o"])
        with1Header.response = .stub(body: "1 header")

        var with2Headers = baseCall
        with2Headers.lookup = .stub(path: nil, query: nil, headers: ["h": "2o", "t": "token"])
        with2Headers.response = .stub(body: "2 headers")

        try registerMocks([withoutHeaders, with1Header, with2Headers])
        try assertCall(.PUT, path, headers: ["not": "in any lookup"], response: "without", message: "Headers not in any lookup are ignored")
        try assertCall(.PUT, path, headers: ["t": "token"], response: "without", message: "All headers in lookup must be present to match")
        try assertCall(.PUT, path, headers: ["h": "2o", "not": "in lookup"], response: "1 header", message: "Mathing on 1 header")
        try assertCall(.PUT, path, headers: ["t": "token", "h": "2o"], response: "2 headers", message: "Match when 2 headers are in the call")
    }

    func test_givenHeaderMatches_when2DifferentMatchOnEqualSizeLookup_thenError() throws
    {
        let call1 = CallInfo.stub(path: "b", lookup: .stub(headers: ["d": "4"]))
        let call2 = CallInfo.stub(path: "b", lookup: .stub(headers: ["c": "3"]))
        try registerMocks([call1, call2])
        try assertErrorConflict(call1.method, "b", headers: ["d": "4", "c": "3"], message: "Multiple match is a conflict error")
    }

    func test_givenHeaderOrQueryMathces_when2DifferentMathcOnEqualSizeLookup_thenError() throws
    {
        let call1 = CallInfo.stub(path: "b", lookup: .stub(headers: ["d": "4"]))
        let call2 = CallInfo.stub(path: "b", lookup: .stub(query: ["c": "3"]))
        try registerMocks([call1, call2])
        try assertErrorConflict(call1.method, "b?c=3", headers: ["d": "4"], message: "Multiple match is a conflict error")
    }

    // MARK: - Mathcing on Body
    func assertMatchingBody(body: Data, headers: HTTPHeaders, message: String, testName: String = #function) throws
    {
        let lookup = CallLookup.stub(body: String(data: body, encoding: .utf8))
        let call = CallInfo.stub(lookup: lookup, response: .stub(body: "ok"))
        try registerMocks(call)
        try assertCall(call.method, call.path, headers: headers, body: body, response: "ok", message: "\(message) :: \(testName)", function: "")
    }

    func test_givenLookupStringBody_whenNoBodyToMatch_thenNoMatch() throws
    {
        let lookup = CallLookup.stub(body: "bob")
        let call = CallInfo.stub(lookup: lookup, response: .stub(body: "ok"))
        try registerMocks(call)
        try assertErrorNotFound(call.method, call.path, message: "Lookup body must be equal to have a match")
    }

    func test_givenStringBody_whenExactBody_thenMatch() throws
    {
        try assertMatchingBody(body: "bob".data(using: .utf8)!, headers: contentTypeTextPlain, message: "Plain Text Body matches when equals")
    }

    func test_givenJSONObjectBody_whenExactBody_thenMatch() throws
    {
        let body = try JSONEncoder().encode(JSONBody(id: "\(Int.random(in: 1 ... 234))", isSomething: false))
        try assertMatchingBody(body: body, headers: contentTypeJSON, message: "Simple JSON object Matches when equals")
    }

    func test_givenJSONObjectBodyWithInnerJSON_whenExactBody_thenMatch() throws
    {
        let bodies = JSONBodies(bodies: [JSONBody(id: "\(Int.random(in: 1 ... 53))"), JSONBody(id: "2"), JSONBody(id: "3")])
        let body = try JSONEncoder().encode(bodies)
        try assertMatchingBody(body: body, headers: contentTypeJSON, message: "Complex JSON with inner JSON Array Matches when equals")
    }

    func test_givenJSONArrayBody_whenExactBody_thenMatch() throws
    {
        let matchingBody = [JSONBody(id: "\(Int.random(in: 1 ... 324))"), JSONBody(id: "2"), JSONBody(id: "3")]
        let body = try JSONEncoder().encode(matchingBody)
        try assertMatchingBody(body: body, headers: contentTypeJSON, message: "Root JSON Array Matches when Equals")
    }

    func test_givenJSONArrayBody_whenNotInSameOrder_thenNoMatch() throws
    {
        let lookupBody = try JSONEncoder().encode([JSONBody(id: "1"), JSONBody(id: "2")])
        let outOfOrderBody = try JSONEncoder().encode([JSONBody(id: "2"), JSONBody(id: "1")])
        let call = CallInfo.stub(lookup: .stub(body: String(data: lookupBody, encoding: .utf8)))
        try registerMocks(call)
        try assertErrorNotFound(call.method, call.path, body: outOfOrderBody, message: "Body JSON Array out of order Don't match")
    }

    func test_given2PossibleMatch_when1MatchOnBodyOtherOnMultipleOther_thenBodyMatchWins() throws
    {
        let body = try JSONEncoder().encode(JSONBody(id: "\(Int.random())"))
        let lookupBodyCall = CallInfo.stub(lookup: .stub(body: String(data: body, encoding: .utf8)), response: .stub(body: "matchOnBody"))
        let callWithout = CallInfo.stub(lookup: .stub(query: ["a": "a", "b": "b", "c": "c"], headers: contentTypeTextPlain), response: .stub(body: "matchOnQuery"))
        try registerMocks([lookupBodyCall, callWithout])
        try assertCall(
            callWithout.method,
            "\(callWithout.path)?a=a&b=b&c=c",
            headers: contentTypeTextPlain,
            body: body,
            response: "matchOnBody",
            message: "A matching body out weigth multiple query and headers match"
        )
    }

    func test_when2MatchWithBody_thenOtherLookupItemCanBreakTheTie() throws
    {
        let body = try JSONEncoder().encode(JSONBody(id: "\(Int.random())"))
        let bodyCall = CallInfo.stub(lookup: .stub(body: String(data: body, encoding: .utf8)), response: .stub(body: "onlyBodyMatch"))
        let queryCall = CallInfo.stub(lookup: .stub(query: ["1": "a"], body: String(data: body, encoding: .utf8)), response: .stub(body: "QUERY"))
        let headerCall = CallInfo.stub(lookup: .stub(headers: contentTypeTextPlain, body: String(data: body, encoding: .utf8)), response: .stub(body: "HEADER"))
        try registerMocks([bodyCall, queryCall, headerCall])

        try assertCall(bodyCall.method, "\(bodyCall.path)?1=a", headers: contentTypeJSON, body: body, response: "QUERY", message: "Query lookup can be added up to body match")
        try assertCall(bodyCall.method, bodyCall.path, headers: contentTypeTextPlain, body: body, response: "HEADER", message: "Header lookup can be added up to body match")
    }

    func test_when2MatchingBody_thenDuplicateError() throws
    {
        let body = try JSONEncoder().encode(JSONBody(id: "\(Int.random())"))
        let firstCall = CallInfo.stub(lookup: .stub(body: String(data: body, encoding: .utf8)), response: .stub(body: "first call"))
        let secondCall = CallInfo.stub(lookup: .stub(body: String(data: body, encoding: .utf8)), response: .stub(body: "second call"))
        try registerMocks([firstCall, secondCall])
        try assertErrorConflict(firstCall.method, firstCall.path, body: body, message: "Same body match result in duplication error")
    }

    // MARK: - Conflict Error Content
    func test_whenConflictError_thenRetrunConflictingMatchesInformations() throws
    {
        func assert_infoSummary(for call: CallInfo, in error: ConflictError) throws
        {
            let summary = try XCTUnwrap(
                error.conflictingMatches.first(where: { sum in
                    guard let idString = sum.callInfoID else { return false }
                    return idString == call.id
                }),
                "An InfoSummary mathching the CallInfo is returned in the error"
            )
            XCTAssertEqual(summary.path, resolve(path: call.path, mapping: call.lookup?.path), "Path in summary is same as in call (resolved)")
            XCTAssertEqual(summary.method, call.method, "Method in summary is same as in call")
            XCTAssertEqual(summary.lookup, call.lookup, "Lookup in summary is same as in call")
        }

        let conflict1 = CallInfo.stub(
            id: UUID(),
            path: "p/:a/b",
            method: .PUT,
            lookup: .stub(
                path: [":a": "a"],
                query: ["r2": "d2"],
                headers: ["h1": "big"]
            )
        )
        let conflict2 = CallInfo.stub(
            id: UUID(),
            path: "p/a/:b",
            method: .PUT,
            lookup: .stub(
                path: [":b": "b"],
                query: ["c3": "po"],
                headers: ["p": "par"]
            )
        )
        let notInConflict = CallInfo.stub(path: "other/path/NOT/conflicting")
        try registerMocks([conflict1, notInConflict, conflict2])

        try app.test(
            conflict1.method,
            "p/a/b?c3=po&r2=d2",
            headers: ["h1": "big", "p": "par"],
            afterResponse: { response in
                let error = try response.content.decode(ConflictError.self)

                try assertBaseMultipleMatchError(in: response)
                XCTAssertEqual(error.conflictingMatches.count, 2, "Number of conflicting matches")
                try assert_infoSummary(for: conflict1, in: error)
                try assert_infoSummary(for: conflict2, in: error)
            }
        )
    }

    func test_whenConflictError_thenReturnInformationAboutTheRequestGeneratingTheConflict() throws
    {
        let callReference = CallInfo.stub(path: "a/valid/path", method: .DELETE)
        let call2 = callReference
        try registerMocks([callReference, call2])

        try app.test(callReference.method, "a/valid/path", headers: ["h1": "1"], afterResponse: { response in
            let error = try response.content.decode(ConflictError.self)
            let requestSummary = error.requestToMatch

            XCTAssertEqual(requestSummary.method, callReference.method, "Used method is returned")
            XCTAssertEqual(requestSummary.url, "a/valid/path", "Path of the request is returned")
            XCTAssertEqual(requestSummary.headers.count, 2)
            XCTAssertEqual(requestSummary.headers["h1"], ["1"], "Custom provided header info is returned")
            XCTAssertTrue(requestSummary.headers.contains(name: "content-length"), "System added header")
        })
    }
}
