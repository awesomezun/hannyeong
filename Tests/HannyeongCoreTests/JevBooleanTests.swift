import Foundation
import XCTest
@testable import HannyeongCore

private final class BooleanProtocol: URLProtocol {
    static var probability = 0.2
    static var captured: JevBooleanRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data: Data
            if let body = request.httpBody { data = body }
            else {
                let stream = request.httpBodyStream!
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096), bytes = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
                data = bytes
            }
            Self.captured = try JSONDecoder().decode(JevBooleanRequest.self, from: data)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let result = Data("{\"model\":\"jev-1.13.0\",\"answers\":{\"keep_english\":{\"type\":\"noul\",\"noul\":\(Self.probability)}},\"usage\":{\"input_tokens\":10}}".utf8)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class JevBooleanTests: XCTestCase {
    func testNoulRequestAndBothOutcomesForAmbiguousGo() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BooleanProtocol.self]
        let client = JevBooleanClient(session: URLSession(configuration: configuration))
        for (probability, expected) in [(0.2, "해"), (0.9, "go")] {
            BooleanProtocol.probability = probability
            let decision = try await client.decide(raw: "go", before: "숙제부터 ", apiKey: "test-only")
            XCTAssertEqual(decision.predicted, expected)
            XCTAssertEqual(decision.keepEnglish, expected == "go")
            XCTAssertEqual(decision.englishProbability, probability)
            let request = try XCTUnwrap(BooleanProtocol.captured)
            XCTAssertEqual(request.state.raw, "go")
            XCTAssertEqual(request.state.hangul, "해")
            XCTAssertEqual(request.state.before, "숙제부터 ")
            XCTAssertEqual(request.questions["keep_english"]?.type, "noul")
            XCTAssertEqual(Set(try XCTUnwrap(request.questions["keep_english"]?.criteria).keys), ["true", "false"])
        }
    }
}
