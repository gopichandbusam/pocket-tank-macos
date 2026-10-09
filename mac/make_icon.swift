import AppKit
import Foundation

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func ellipse(_ rect: NSRect, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

func drawFish(x: CGFloat, y: CGFloat, scale: CGFloat, tint: NSColor, facingRight: Bool = true) {
    let body = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 94 * scale, height: 53 * scale))
    tint.setFill()
    body.fill()
    let tail = NSBezierPath()
    if facingRight {
        tail.move(to: NSPoint(x: x + 3 * scale, y: y + 26 * scale))
        tail.line(to: NSPoint(x: x - 27 * scale, y: y + 46 * scale))
        tail.line(to: NSPoint(x: x - 24 * scale, y: y + 8 * scale))
    } else {
        tail.move(to: NSPoint(x: x + 91 * scale, y: y + 26 * scale))
        tail.line(to: NSPoint(x: x + 121 * scale, y: y + 46 * scale))
        tail.line(to: NSPoint(x: x + 118 * scale, y: y + 8 * scale))
    }
    tail.close()
    tint.setFill()
    tail.fill()
    ellipse(NSRect(x: x + (facingRight ? 68 : 15) * scale, y: y + 32 * scale,
                   width: 7 * scale, height: 7 * scale), color(0x12344A))
    let fin = NSBezierPath()
    fin.move(to: NSPoint(x: x + 45 * scale, y: y + 46 * scale))
    fin.curve(to: NSPoint(x: x + 61 * scale, y: y + 29 * scale),
              controlPoint1: NSPoint(x: x + 57 * scale, y: y + 50 * scale),
              controlPoint2: NSPoint(x: x + 65 * scale, y: y + 39 * scale))
    fin.curve(to: NSPoint(x: x + 42 * scale, y: y + 34 * scale),
              controlPoint1: NSPoint(x: x + 59 * scale, y: y + 21 * scale),
              controlPoint2: NSPoint(x: x + 48 * scale, y: y + 28 * scale))
    fin.close()
    color(0xFFF1C4).setFill()
    fin.fill()
}

func render(size: Int, destination: URL) throws {
    let side = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0) else {
        throw NSError(domain: "PocketTankIcon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    color(0x102F46).setFill()
    NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22).fill()
    let inset = side * 0.105
    let tank = NSRect(x: inset, y: inset * 0.9, width: side - inset * 2, height: side - inset * 1.8)
    let tankPath = NSBezierPath(roundedRect: tank, xRadius: side * 0.17, yRadius: side * 0.17)
    NSGraphicsContext.saveGraphicsState()
    tankPath.addClip()
    NSGradient(colors: [color(0x9AE6E2), color(0x2C9FB7), color(0x17648B)])!.draw(in: tank, angle: 90)
    // Light rays and soft underwater reflections.
    color(0xD4FFF3, alpha: 0.28).setFill()
    let ray = NSBezierPath()
    ray.move(to: NSPoint(x: tank.minX + side * 0.15, y: tank.maxY))
    ray.line(to: NSPoint(x: tank.minX + side * 0.32, y: tank.maxY))
    ray.line(to: NSPoint(x: tank.minX + side * 0.56, y: tank.minY))
    ray.line(to: NSPoint(x: tank.minX + side * 0.36, y: tank.minY))
    ray.close()
    ray.fill()
    // Sandy floor and a small plant.
    color(0xE7CB83).setFill()
    let sand = NSBezierPath()
    sand.move(to: NSPoint(x: tank.minX, y: tank.minY))
    sand.line(to: NSPoint(x: tank.maxX, y: tank.minY))
    sand.line(to: NSPoint(x: tank.maxX, y: tank.minY + side * 0.16))
    sand.curve(to: NSPoint(x: tank.minX, y: tank.minY + side * 0.19),
               controlPoint1: NSPoint(x: tank.minX + side * 0.35, y: tank.minY + side * 0.1),
               controlPoint2: NSPoint(x: tank.minX + side * 0.6, y: tank.minY + side * 0.24))
    sand.close()
    sand.fill()
    color(0x267F6A).setStroke()
    let plant = NSBezierPath()
    plant.lineWidth = side * 0.035
    plant.move(to: NSPoint(x: tank.minX + side * 0.25, y: tank.minY + side * 0.12))
    plant.curve(to: NSPoint(x: tank.minX + side * 0.31, y: tank.minY + side * 0.45),
                controlPoint1: NSPoint(x: tank.minX + side * 0.2, y: tank.minY + side * 0.3),
                controlPoint2: NSPoint(x: tank.minX + side * 0.36, y: tank.minY + side * 0.37))
    plant.move(to: NSPoint(x: tank.minX + side * 0.26, y: tank.minY + side * 0.25))
    plant.curve(to: NSPoint(x: tank.minX + side * 0.14, y: tank.minY + side * 0.39),
                controlPoint1: NSPoint(x: tank.minX + side * 0.15, y: tank.minY + side * 0.29),
                controlPoint2: NSPoint(x: tank.minX + side * 0.13, y: tank.minY + side * 0.36))
    plant.stroke()
    // Two cheerful fish.
    drawFish(x: tank.minX + side * 0.32, y: tank.minY + side * 0.52,
             scale: side / 512 * 0.84, tint: color(0xFF8D52))
    drawFish(x: tank.minX + side * 0.48, y: tank.minY + side * 0.31,
             scale: side / 512 * 0.55, tint: color(0xFFE071), facingRight: false)
    for (bx, by, br) in [(0.7, 0.72, 0.025), (0.76, 0.82, 0.016), (0.22, 0.63, 0.015)] {
        let bubble = NSRect(x: tank.minX + side * bx, y: tank.minY + side * by,
                            width: side * br * 2, height: side * br * 2)
        color(0xE9FFFF, alpha: 0.8).setStroke()
        let circle = NSBezierPath(ovalIn: bubble)
        circle.lineWidth = max(1, side * 0.008)
        circle.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    color(0xD9F6EC, alpha: 0.9).setStroke()
    tankPath.lineWidth = max(2, side * 0.022)
    tankPath.stroke()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PocketTankIcon", code: 2)
    }
    try data.write(to: destination)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
do {
    for (name, size) in variants {
        try render(size: size, destination: output.appendingPathComponent(name))
    }
} catch {
    fputs("make_icon.swift: \(error)\n", stderr)
    exit(1)
}
