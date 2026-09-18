import Cocoa

// Generates the app's own geometric icon locally. No network or image assets.
guard CommandLine.arguments.count == 2 else { exit(2) }
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.13, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 210, yRadius: 210).fill()
NSColor(calibratedRed: 0.55, green: 0.53, blue: 1, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 168, y: 615, width: 688, height: 88), xRadius: 44, yRadius: 44).fill()
NSColor(calibratedRed: 0.35, green: 0.86, blue: 0.76, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 168, y: 321, width: 164, height: 224), xRadius: 46, yRadius: 46).fill()
NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 378, y: 321, width: 478, height: 88), xRadius: 44, yRadius: 44).fill()
NSBezierPath(roundedRect: NSRect(x: 378, y: 457, width: 478, height: 88), xRadius: 44, yRadius: 44).fill()
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
catch { fputs("Icon write failed: \(error)\n", stderr); exit(1) }
