import Foundation

/// The transport layer for one signed-in server.
///
/// An actor because the token can be replaced mid-flight (sign-out, re-auth) and
/// every request reads it. Item queries live in `JellyfinClient+Library.swift`;
/// this file is transport, auth, and nothing else.
public actor JellyfinClient {

    /// Immutable and Sendable, so views can read the server and user name without
    /// awaiting the actor.
    public nonisolated let session: JellyfinSession
    private var token: String
    private let urlSession: URLSession

    public init(session: JellyfinSession, token: String) {
        self.session = session
        self.token = token

        let config = URLSessionConfiguration.default
        // A LAN server that is asleep should fail fast rather than hang the UI —
        // but 20 seconds was fast enough to fail a *working* one. A sync page of
        // 200 items with Fields, against a library of 44,000 rows, regularly ran
        // past it on a Mac that was busy indexing, and each expiry read to the app
        // as "the server is unreachable". Sixty is still short enough that a
        // genuinely absent server surfaces quickly.
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        // Artwork has its own disk cache in ImagePipeline; a second URL cache
        // would double-store every poster.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
    }

    public func updateToken(_ newToken: String) {
        token = newToken
    }

    // MARK: - Request building

    /// Jellyfin's auth scheme. Modern servers read `Authorization`; the legacy
    /// `X-Emby-Authorization` header is sent too so 10.7-era servers still work.
    static func authorizationValue(deviceId: String, token: String?) -> String {
        var parts = [
            "Client=\"\(headerSafeValue(DeviceIdentity.clientName))\"",
            "Device=\"\(headerSafeValue(DeviceIdentity.deviceName))\"",
            "DeviceId=\"\(headerSafeValue(deviceId))\"",
            "Version=\"\(headerSafeValue(DeviceIdentity.clientVersion))\"",
        ]
        if let token, !token.isEmpty {
            parts.append("Token=\"\(headerSafeValue(token))\"")
        }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    /// Makes a value safe to put inside a quoted MediaBrowser auth parameter.
    ///
    /// This is not defensive tidying — it is the fix for a bug that made signing in
    /// impossible on this machine. macOS names a Mac "Jeremiah’s MacBook Pro" using
    /// a curly apostrophe, U+2019, and `Host.current().localizedName` hands that
    /// straight over. An HTTP header carrying non-ASCII goes out in a form ASP.NET
    /// Core will not parse, so Jellyfin answered **400 before ever looking at the
    /// credentials** — every sign-in attempt failed, and the UI reported it as a
    /// server error, so no password could have worked.
    ///
    /// Worth knowing: `curl` sends the same bytes and gets a normal 401, so a shell
    /// test does *not* reproduce this. Only URLSession does.
    ///
    /// Quotes and commas go too: they are the scheme's own delimiters, and a Mac
    /// named `My "Media" Box, v2` would otherwise split one parameter into three.
    public static func headerSafeValue(_ value: String) -> String {
        // Typographic punctuation has obvious ASCII equivalents; mapping it keeps
        // the name readable in the server's device list instead of gutting it.
        let folded = value
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "")
            .replacingOccurrences(of: "\u{201D}", with: "")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")

        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            // Printable ASCII only, minus the delimiters the scheme depends on.
            guard scalar.isASCII, scalar.value >= 0x20, scalar.value != 0x7F,
                  scalar != "\"", scalar != ",", scalar != "\\"
            else { return " " }
            return Character(scalar)
        }

        let collapsed = String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed.isEmpty ? "Mac" : collapsed
    }

    /// The Authorization header as it would be sent, for diagnostics only.
    public static func diagnosticAuthorizationValue() -> String {
        authorizationValue(deviceId: DeviceIdentity.deviceId, token: nil)
    }

    nonisolated func makeRequest(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String = "application/json",
        authToken: String?,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: session.serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw JellyfinError.invalidServerURL(session.serverURL.absoluteString)
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw JellyfinError.invalidServerURL(session.serverURL.absoluteString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        let auth = Self.authorizationValue(deviceId: session.deviceId, token: authToken)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(auth, forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        // Per-request, for the few endpoints that do real work before answering.
        // The session default is 60s, which is right for reads and wrong for a
        // scrape: Jellyfin's identify endpoint re-matches the item and downloads
        // every image the provider offers before it replies.
        if let timeout { request.timeoutInterval = timeout }
        return request
    }

    public var accessToken: String { token }

    // MARK: - Execution

    /// - Parameter caller: filled in by the compiler. A failing request used to log
    ///   its path and status and nothing else, which is enough to see *that*
    ///   something 404s and useless for finding out *why*: `Users/x/Items/y -> 404`
    ///   could have come from any of six call sites. The function name costs nothing
    ///   and turns every future mystery in the log into a place in the code.
    func send<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        caller: String = #function
    ) async throws -> T {
        let request = try makeRequest(
            path: path, method: method, query: query, body: body, authToken: token
        )
        let data = try await Self.execute(request, on: urlSession, caller: caller)
        return try Self.decode(type, from: data, context: path)
    }

    /// The response bytes, undecoded.
    ///
    /// For the one thing a typed model cannot do: editing an item. `JellyfinItem`
    /// decodes about forty of `BaseItemDto`'s hundred-odd fields, and the update
    /// endpoint takes the *whole* object — so posting back a re-encoded model would
    /// silently clear every field this app never learned about. Reading the raw JSON,
    /// changing the few keys being edited and posting that back is the only way to
    /// edit one field without destroying sixty others.
    func sendData(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        caller: String = #function
    ) async throws -> Data {
        let request = try makeRequest(
            path: path, method: method, query: query, body: body, authToken: token
        )
        return try await Self.execute(request, on: urlSession, caller: caller)
    }

    /// For endpoints that return 204 with no body.
    func sendVoid(
        path: String,
        method: String = "POST",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String = "application/json",
        timeout: TimeInterval? = nil,
        caller: String = #function
    ) async throws {
        let request = try makeRequest(
            path: path, method: method, query: query, body: body,
            contentType: contentType, authToken: token, timeout: timeout
        )
        _ = try await Self.execute(request, on: urlSession, caller: caller)
    }

    static func execute(
        _ request: URLRequest, on urlSession: URLSession, caller: String = "?"
    ) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw JellyfinError.notReachable(underlying: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { return data }
        if !(200..<300).contains(http.statusCode) {
            // Logged unconditionally, to stderr. A failing request that leaves no
            // trace is how sign-in stayed broken through every phase of this
            // project: the UI showed one sentence and there was no way to tell a
            // rejected password from a malformed request.
            Diagnostics.log(
                "[http] \(request.httpMethod ?? "GET")"
                + " \(request.url?.path ?? "?") -> \(http.statusCode)"
                + " (from \(caller))"
            )
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw JellyfinError.unauthorized
        default:
            throw JellyfinError.httpError(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
    }

    // MARK: - Decoding

    /// Jellyfin emits ISO-8601 with a variable number of fractional-second digits
    /// and sometimes none at all, which `.iso8601` alone rejects. Rather than lose
    /// an entire library page to one odd timestamp, unparseable dates decode as nil
    /// via the optional properties that use them.
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseJellyfinDate(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unparseable date \(raw)")
                )
            }
            return date
        }
        return decoder
    }()

    /// `Date.ISO8601FormatStyle` is a Sendable struct, unlike `ISO8601DateFormatter`,
    /// so these can be shared across the concurrent requests the client makes without
    /// a lock or an unsafe opt-out.
    private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    /// Jellyfin emits three shapes depending on version and field: seven-digit
    /// fractional seconds, whole seconds, and — for `PremiereDate` on some
    /// libraries — no timezone designator at all.
    public static func parseJellyfinDate(_ raw: String) -> Date? {
        if let date = try? withFractionalSeconds.parse(raw) { return date }
        if let date = try? withoutFractionalSeconds.parse(raw) { return date }

        // No zone designator. Jellyfin stores UTC, so assume it rather than drop
        // the value. Only the part after the date is inspected, so the date's own
        // hyphens are not mistaken for a negative offset.
        let afterDate = raw.dropFirst(10)
        let hasZone = afterDate.contains("Z") || afterDate.contains("+") || afterDate.contains("-")
        if !hasZone {
            if let date = try? withFractionalSeconds.parse(raw + "Z") { return date }
            if let date = try? withoutFractionalSeconds.parse(raw + "Z") { return date }
        }
        return nil
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw JellyfinError.decodingFailed(
                context: context,
                underlying: String(describing: error)
            )
        }
    }
}
