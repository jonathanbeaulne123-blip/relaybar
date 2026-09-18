import XCTest
@testable import RelayCore

final class PluginTests: XCTestCase {
    func testPluginManifestValidation() {
        var manifest = PluginManifest(
            name: "Test",
            version: "1.0.0",
            description: "A test plugin",
            commands: []
        )
        XCTAssertThrowsError(try manifest.validate(), "Empty commands should throw")
        
        manifest.commands.append(PluginCommand(name: "Test Cmd", script: "test.sh"))
        XCTAssertNoThrow(try manifest.validate())
        
        // Path traversal rejection
        manifest.commands = [PluginCommand(name: "Sneaky", script: "../etc/passwd")]
        XCTAssertThrowsError(try manifest.validate())
    }
}
