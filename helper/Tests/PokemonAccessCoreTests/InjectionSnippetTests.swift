import XCTest
@testable import PokemonAccessCore

final class InjectionSnippetTests: XCTestCase {
    func testDofileUsesLongBracketsSoSpacesAndQuotesNeedNoEscaping() {
        XCTAssertEqual(InjectionSnippet.dofile(path: "/Users/x/Pokemon Access/lua/pokemon-access.lua"),
                       "dofile([==[/Users/x/Pokemon Access/lua/pokemon-access.lua]==])")
        XCTAssertEqual(InjectionSnippet.dofile(path: "/a/it's \"here\".lua"),
                       "dofile([==[/a/it's \"here\".lua]==])")
    }
}
