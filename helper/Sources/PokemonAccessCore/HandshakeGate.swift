/// The first message on a connection must be HELLO, carrying the launch token
/// when the helper was started with one. Anything else (another local process,
/// a browser speaking HTTP) is dropped without disturbing the real client.
public enum HandshakeGate {
    public static func accepts(first message: LuaMessage, expectedToken: String?) -> Bool {
        guard case let .hello(_, _, _, token) = message else { return false }
        guard let expectedToken else { return true }
        return token == expectedToken
    }

    /// 32 random alphanumeric characters.
    public static func makeToken() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
    }
}
