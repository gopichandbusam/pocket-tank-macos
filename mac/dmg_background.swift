import AppKit
import Foundation
let destination=URL(fileURLWithPath:CommandLine.arguments[1])
let width=640, height=500
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
func color(_ hex:UInt32)->NSColor { NSColor(calibratedRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
color(0xEAF4F3).setFill(); NSBezierPath(rect:NSRect(x:0,y:0,width:640,height:500)).fill()
func text(_ value:String,_ y:CGFloat,_ size:CGFloat,_ tint:UInt32,_ weight:NSFont.Weight = .regular) {
 let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color(tint)]
 let measured=(value as NSString).size(withAttributes:attributes)
 (value as NSString).draw(at:NSPoint(x:(640-measured.width)/2,y:y),withAttributes:attributes)
}
text("Pocket Tank",428,31,0x173D47,.semibold)
text("Drag Pocket Tank to Applications",388,17,0x275761,.medium)
let arrow=NSBezierPath(); arrow.move(to:NSPoint(x:287,y:287));arrow.line(to:NSPoint(x:357,y:287));arrow.lineWidth=4;arrow.lineCapStyle = .round;color(0x4A8892).setStroke();arrow.stroke()
let head=NSBezierPath();head.move(to:NSPoint(x:345,y:300));head.line(to:NSPoint(x:360,y:287));head.line(to:NSPoint(x:345,y:274));head.lineWidth=4;head.lineJoinStyle = .round;color(0x4A8892).setStroke();head.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:destination)
