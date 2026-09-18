import Cocoa

// Type-check only: never launched and no user data or permissions are accessed.
// Importing the actual bridge reproduces the user's generate-pch failure early.
enum RelayBarCompileProbe {
    static let applicationType: AnyClass = NSApplication.self
    static let bridgeType: AnyClass = RBBridge.self
}
