import Foundation
import Combine

/// Singleton that handles `remindian://` URL scheme callbacks for OAuth flows.
class OAuthCallbackHandler: ObservableObject {
    static let shared = OAuthCallbackHandler()

    @Published var tickTickAuthCode: String?

    private init() {}

    /// Route an incoming URL to the appropriate handler.
    func handle(url: URL) {
        debugLog("[OAuth] Received callback: \(url.absoluteString)")

        guard url.scheme == "remindian" else { return }

        switch url.host {
        case "oauth":
            handleOAuthCallback(url: url)
        default:
            debugLog("[OAuth] Unknown host: \(url.host ?? "nil")")
        }
    }

    private func handleOAuthCallback(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.pathComponents.dropFirst().first // e.g. "ticktick"

        switch path {
        case "ticktick":
            if let code = components?.queryItems?.first(where: { $0.name == "code" })?.value {
                debugLog("[OAuth] TickTick auth code received")
                tickTickAuthCode = code
            } else {
                debugLog("[OAuth] TickTick callback missing code parameter")
            }
        default:
            debugLog("[OAuth] Unknown OAuth provider: \(path ?? "nil")")
        }
    }
}
