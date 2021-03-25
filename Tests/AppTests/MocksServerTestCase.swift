//
//  File.swift
//
//
//  Created by Vincent Bernier on 2021-03-10.
//

@testable import App
import XCTVapor

class MocksServerTestCase: XCTestCase
{
    var app: Application!
    var contentTypeJSON: HTTPHeaders { ["Content-Type": "application/json"] }

    override func setUpWithError() throws
    {
        try super.setUpWithError()
        app = Application(.testing)
        try configure(app)
    }

    override func tearDownWithError() throws
    {
        app.shutdown()
        app = nil
        try super.tearDownWithError()
    }

    func registerMocks(_ callInfo: CallInfo) throws { try registerMocks([callInfo]) }

    // Abstract the Data Seeding process
    func registerMocks(_ callInfos: [CallInfo]) throws
    {
        try callInfos.forEach
        { callInfo in
            try app
                .test(.POST, "mocks", headers: contentTypeJSON, body: callInfo.responseBodyBuffer, afterResponse: { response in
                    XCTAssertEqual(response.status, .ok)
                })
        }
    }

    func registerMocks(_ callInfo: CallInfo, afterResponse: (XCTHTTPResponse) throws -> Void) throws
    {
        try app
            .test(.POST, "mocks", headers: contentTypeJSON, body: callInfo.responseBodyBuffer, afterResponse: { response in
                try afterResponse(response)
            })
    }
}
