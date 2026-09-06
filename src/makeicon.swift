import AppKit

// Claude 오렌지 라운드 스퀘어 + 스파크 글리프. macOS 아이콘 그리드(88% 캔버스)를 따른다.
func draw(_ size: Int) -> Data {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)

    let grad = NSGradient(colors: [NSColor(srgbRed: 0.910, green: 0.545, blue: 0.396, alpha: 1),
                                   NSColor(srgbRed: 0.780, green: 0.396, blue: 0.271, alpha: 1)])
    grad?.draw(in: path, angle: -90)

    // 스파크: 네 방향으로 오목한 별
    let c = NSPoint(x: rect.midX, y: rect.midY)
    let r = rect.width * 0.30
    let k = r * 0.30
    let spark = NSBezierPath()
    spark.move(to: NSPoint(x: c.x, y: c.y + r))
    spark.curve(to: NSPoint(x: c.x + r, y: c.y),
                controlPoint1: NSPoint(x: c.x + k, y: c.y + k), controlPoint2: NSPoint(x: c.x + k, y: c.y + k))
    spark.curve(to: NSPoint(x: c.x, y: c.y - r),
                controlPoint1: NSPoint(x: c.x + k, y: c.y - k), controlPoint2: NSPoint(x: c.x + k, y: c.y - k))
    spark.curve(to: NSPoint(x: c.x - r, y: c.y),
                controlPoint1: NSPoint(x: c.x - k, y: c.y - k), controlPoint2: NSPoint(x: c.x - k, y: c.y - k))
    spark.curve(to: NSPoint(x: c.x, y: c.y + r),
                controlPoint1: NSPoint(x: c.x - k, y: c.y + k), controlPoint2: NSPoint(x: c.x - k, y: c.y + k))
    NSColor.white.withAlphaComponent(0.96).setFill()
    spark.fill()

    img.unlockFocus()
    let tiff = img.tiffRepresentation!
    return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                     ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
                     ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! draw(size).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
