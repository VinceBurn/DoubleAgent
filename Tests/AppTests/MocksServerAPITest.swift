@testable import App
import XCTVapor

final class MocksServerAPITest: MocksServerTestCase
{
    func test_getAllMocks_whenNone_thenNoResult() throws
    {
        try app.test(.GET, "mocks", afterResponse: { response in
            let responses = try response.content.decode([CallInfo].self)
            XCTAssertEqual(response.status, .ok)
            XCTAssertEqual(responses.count, 0)
        })
    }

    func test_createOneCallInfo_oneIsRetreivable() throws
    {
        try registerMocks(CallInfo.stub())
        try app
            .test(.GET, "mocks", afterResponse: { response in
                let responses = try response.content.decode([CallInfo].self)
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(responses.count, 1)
            })
    }

    func test_givenCreatedRoute_whenResetAll_thenAllRoutesRemoved() throws
    {
        try registerMocks(CallInfo.stub())
        try app
            .test(.GET, "mocks", afterResponse: { response in
                XCTAssertEqual(response.status, .ok)
                let responses = try response.content.decode([CallInfo].self)
                XCTAssertEqual(responses.count, 1)
            })
            .test(.DELETE, "mocks/resetAll")
            .test(.GET, "mocks", afterResponse: { response in
                XCTAssertEqual(response.status, .ok)
                let responses = try response.content.decode([CallInfo].self)
                XCTAssertEqual(responses.count, 0)
            })
    }

    func test_createOneCallInfo_thenItCanBeRetreive() throws
    {
        let input = CallInfo.stub(
            id: UUID(),
            path: "a/w",
            method: .COPY
        )
        try registerMocks(input)
        try app
            .test(.GET, "mocks", afterResponse: { response in
                XCTAssertEqual(response.status, .ok)
                let infos = try response.content.decode([CallInfo].self)
                XCTAssertEqual(infos.count, 1)
                let output = try XCTUnwrap(infos.first)
                XCTAssertEqual(output, input)
            })
    }

    func test_create_whenWrongFormat_thenError() throws
    {
        let data = try XCTUnwrap(#"{"bad_format": true}"#.data(using: .utf8))
        let input = ByteBuffer(data: data)
        try app.test(.POST, "mocks", headers: contentTypeJSON, body: input, afterResponse: { response in
            XCTAssertNotEqual(response.status, .ok)
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains(#""error":true"#))
            // TODO: Have an error message that explain how to configure data for the server (when fully defined)
        })
    }

    func test_help() throws
    {
        try app.test(.GET, "mocks/help", afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertEqual(response.body.string, "TODO: Make Instruction")
        })
    }

//    func test_create_whenAddingSameCallInfo() throws
//    { // may not be possible to fully cover all cases, maybe it is better to send error when a call is made that match multiple values
    // TODO: Add header and response code to response before testing this one
//        XCTFail("What should be the result? Override or Error")
//    }
}
