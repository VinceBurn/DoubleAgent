//
//  File.swift
//
//
//  Created by Vincent Bernier on 2021-03-10.
//

@testable import App
import Codability
import XCTVapor

final class MocksServerResponseTest: MocksServerTestCase
{
    func test_whenNoMatch_thenError() throws
    {
        let methods: [HTTPMethod] = [.GET, .POST, .PUT, .DELETE, .PATCH]
        try methods.forEach
        { method in
            try app.test(method, "some/path")
            { response in
                XCTAssertEqual(response.status, .notFound, "\(method)")
                XCTAssertTrue(response.body.string.contains(#""error":true"#), "\(method)")
                XCTAssertTrue(response.body.string.contains(#""reason":"\#(HTTPStatus.notFound.reasonPhrase)"#), "\(method)")
            }
        }
    }

    func test_givenPathAndMethod_whenExactMatch_thenResponse() throws
    {
        let inputs: [(route: String, method: HTTPMethod)] = [
            ("/slash/start", .GET),
            ("no/slash", .POST),
            ("slash/at/end/", .PUT),
            ("/slash/both/ends/", .DELETE),
            ("/some/path/", .PATCH),
        ]
        try inputs.forEach
        { route, method in
            let body = "Test for \(method.rawValue)"
            let info = CallInfo
                .stub(
                    path: route,
                    method: method,
                    response: CallResponse
                        .stub(body: AnyCodable(body))
                )
            try registerMocks(info)
            try app
                .test(method, route, afterResponse: { response in
                    XCTAssertEqual(response.status, .ok, "Path is found and something is returned: route -> \(route) :: method -> \(method.rawValue)")
                    XCTAssertEqual(response.headers.contentType, .plainText, "Response Content is Text")
                    XCTAssertEqual(response.body.string, "\(body)", "Response is returned as Text")
                })
        }
    }

    func test_givenSamePathWithDifferentMethod_thenReponseIsForTheMethod() throws
    {
        let testDatas: [(method: HTTPMethod, body: [String: String])] = [
            (.GET, ["key": "get"]),
            (.POST, ["key": "post"]),
            (.PUT, ["key": "put"]),
        ]
        let sameRoute = "same/route"
        try registerMocks(
            testDatas.map(
                { method, body in
                    return CallInfo
                        .stub(
                            path: sameRoute,
                            method: method,
                            response: CallResponse.stub(body: AnyCodable(body))
                        )
                }))

        try testDatas.forEach({ method, body in
            try app
                .test(method, sameRoute, afterResponse: { response in
                    XCTAssertEqual(response.status, .ok, "Was found")
                    let responseObject = try response.content.decode(AnyCodable.self)
                    let responseDic = try XCTUnwrap(responseObject.value as? [String: String])
                    XCTAssertEqual(responseDic, body, "Payload associate with the method is returned")
                })
        })
    }

    func test_givenMockResponseWithStatusCode_whenReturn_useTheStatusCode() throws
    {
        let calls = [
            ("no/content", HTTPStatus.noContent),
            ("bad/request", HTTPStatus.badRequest),
            ("unavailable", HTTPStatus.serviceUnavailable),
        ]
        .map
        { route, status in
            return CallInfo.stub(
                path: route,
                method: .GET,
                response: CallResponse.stub(status: status)
            )
        }
        try registerMocks(calls)
        try calls.forEach
        { callInfo in
            try app
                .test(callInfo.method, callInfo.path, afterResponse: { response in
                    XCTAssertEqual(response.status, callInfo.response?.status, "Response Status is the one set for the resonse")
                })
        }
    }

    func test_givenMockResponseWithHeaders_whenReturn_sendHeaders() throws
    {
        let inputHeaders = HTTPHeaders([("content-type", "application/json"), ("key", "value"), ("key", "val2"), ("other", "v"), ("content-type", "application/zip")])
        let controlHeaders = HTTPHeaders([("key", "val2"), ("other", "v"), ("Content-Type", "application/zip")])
        let info = CallInfo.stub(
            response: CallResponse.stub(headers: inputHeaders)
        )

        try registerMocks(info)
        try app
            .test(info.method, info.path, afterResponse: { response in
                let result = response.headers
                try controlHeaders.forEach
                { header in
                    let allValues = result[header.name]
                    XCTAssertEqual(allValues.count, 1, "No key duplication :: key [\(header.name)]")
                    let value = try XCTUnwrap(allValues.first)
                    XCTAssertEqual(value, header.value, "Value is set :: value [\(header.value)]")
                }
            })
    }

    func test_givenMockResponseWithBody_whenReturned_contentTypeInferredFromBody() throws
    {
        let inputs: [(body: AnyCodable, type: HTTPMediaType, route: String)] = [
            ("some text", .plainText, "1"),
            (1, .plainText, "2"),
            (true, .plainText, "3"),
            (#"{"key": "some JSON"}"#, .plainText, "4"),
            (["key": "some JSON Value", "b": true], .json, "5"),
            ([1, 2, 3], .json, "6"),
        ]
        let calls = inputs.map
        { body, type, route in
            return CallInfo.stub(path: route, method: .GET, response: CallResponse.stub(body: body))
        }
        try registerMocks(calls)
        try inputs.forEach
        { body, type, route in
            try app
                .test(.GET, route, afterResponse: { response in
                    XCTAssertEqual(response.headers.contentType, type, "Input \(body.value) is of type: \(type.description)")
                })
        }
    }

    func test_givenNoProvidedResponse_whenRouteMatch_thenDefault() throws
    {
        let call = CallInfo.stub(response: nil)
        try registerMocks(call)
        try app
            .test(call.method, call.path, afterResponse: { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers.contentType, .plainText, "Default content type")
                XCTAssertEqual(response.body.string, "", "Default body is empty")
                let headers = response.headers
                XCTAssertEqual(headers.count, 3, "Only default headers are present")
                XCTAssertTrue(headers.contains(name: "content-type"))
                XCTAssertTrue(headers.contains(name: "content-length"))
                XCTAssertTrue(headers.contains(name: "mocked-call-id"), "Mock server add information header about the found call")
            })
    }
}
