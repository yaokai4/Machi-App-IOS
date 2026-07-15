import Foundation
import Testing
@testable import Machi

/// Regression coverage for the production-account deletion incident caused by
/// ordinary XCTest processes reusing a persisted production Keychain token.
@MainActor
struct ProductionNetworkSafetyTests {
    @Test func backendPolicyRequiresExplicitSmokeOptInDuringXCTest() {
        let xctestEnvironment = [
            "XCTestConfigurationFilePath": "/tmp/Machi.xctestconfiguration"
        ]
        #expect(!KaiXRuntimeFlags.backendRequestsAllowed(environment: xctestEnvironment))

        let smokeEnvironment = [
            "XCTestConfigurationFilePath": "/tmp/Machi.xctestconfiguration",
            "KAIX_RUN_BACKEND_SMOKE_TESTS": "1"
        ]
        #expect(KaiXRuntimeFlags.backendRequestsAllowed(environment: smokeEnvironment))
        #expect(KaiXRuntimeFlags.backendRequestsAllowed(environment: [:]))
    }

    @Test func ordinaryXCTestRequestIsRejectedBeforeURLSession() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectingURLProtocol.self]
        let client = KaiXAPIClient(session: URLSession(configuration: configuration))

        do {
            _ = try await client.request("GET", "/healthz")
            Issue.record("ordinary XCTest request unexpectedly reached URLSession")
        } catch let error as URLError {
            #expect(error.code == .noPermissionsToReadFile)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

/// A hermetic URLProtocol makes the red test safe: before the production guard
/// exists, the request fails locally instead of ever touching the network.
private final class RejectingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }

    override func stopLoading() {}
}
