// Reproducible vector artwork: no image dependencies, network or runtime cost.
// Reference: Paimon seal, The Goetia (Mathers, 1904), public domain.
import AppKit

let root=URL(fileURLWithPath:CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let navy=NSColor(srgbRed:17/255,green:28/255,blue:39/255,alpha:1)
let ivory=NSColor(srgbRed:232/255,green:231/255,blue:215/255,alpha:1)
let muted=NSColor(srgbRed:110/255,green:131/255,blue:140/255,alpha:1)
var svgPaths=[String]()
func stroke(_ context:CGContext,_ commands:String,_ build:(CGMutablePath)->Void) {
    let path=CGMutablePath(); build(path); context.addPath(path); context.strokePath()
    svgPaths.append("<path d=\"\(commands)\"/>")
}
func circle(_ context:CGContext,_ x:CGFloat,_ y:CGFloat,_ r:CGFloat) {
    context.strokeEllipse(in:CGRect(x:x-r,y:y-r,width:r*2,height:r*2))
    svgPaths.append("<circle cx=\"\(x)\" cy=\"\(y)\" r=\"\(r)\"/>")
}
func sigil(_ c:CGContext) {
    c.setStrokeColor(ivory.cgColor); c.setLineWidth(11); c.setLineCap(.round); c.setLineJoin(.round)
    circle(c,512,512,340)
    // Four circular terminals and parallel diagonals replace the engraved curls.
    for x in [CGFloat(354),459,565,670] {
        circle(c,x,365,28)
        stroke(c,"M \(x) 393 L \(x-42) 520 M \(x-14) 520 L \(x-14) 555") { p in
            p.move(to:CGPoint(x:x,y:393)); p.addLine(to:CGPoint(x:x-42,y:520))
            p.move(to:CGPoint(x:x-14,y:520)); p.addLine(to:CGPoint(x:x-14,y:555))
        }
        circle(c,x-14,574,18)
    }
    stroke(c,"M 286 520 L 738 520 M 310 628 L 714 628 M 354 628 L 354 662 M 670 628 L 670 662") { p in
        p.move(to:CGPoint(x:286,y:520)); p.addLine(to:CGPoint(x:738,y:520))
        p.move(to:CGPoint(x:310,y:628)); p.addLine(to:CGPoint(x:714,y:628))
        for x in [CGFloat(354),670] { p.move(to:CGPoint(x:x,y:628)); p.addLine(to:CGPoint(x:x,y:662)) }
    }
    circle(c,266,520,20); circle(c,758,520,20)
    circle(c,354,684,22); circle(c,670,684,22)
}
func bitmap(width:Int,height:Int,draw:(CGContext)->Void) throws -> Data {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.calibratedRGB,bytesPerRow:0,bitsPerPixel:0)!
    let graphics=NSGraphicsContext(bitmapImageRep:rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=graphics
    let c=graphics.cgContext; c.translateBy(x:0,y:CGFloat(height)); c.scaleBy(x:1,y:-1)
    draw(c); NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using:.png,properties:[:])!
}
let icon=try bitmap(width:1024,height:1024) { c in
    c.setFillColor(navy.cgColor); c.addPath(CGPath(roundedRect:CGRect(x:48,y:48,width:928,height:928),cornerWidth:208,cornerHeight:208,transform:nil)); c.fillPath(); sigil(c)
}
let brand=root.appendingPathComponent("Resources/Brand")
let mark=try bitmap(width:256,height:256) { c in c.scaleBy(x:0.25,y:0.25); sigil(c) }
try mark.write(to:brand.appendingPathComponent("PAIMON-symbol.png"))
svgPaths=Array(svgPaths.prefix(svgPaths.count/2))
try icon.write(to:brand.appendingPathComponent("PAIMON-icon.png"))
let symbol="<g fill=\"none\" stroke=\"#e8e7d7\" stroke-width=\"11\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\(svgPaths.joined())</g>"
let svgHeader="<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\">"
try (svgHeader+"<rect x=\"48\" y=\"48\" width=\"928\" height=\"928\" rx=\"208\" fill=\"#111c27\"/>"+symbol+"</svg>\n").write(to:brand.appendingPathComponent("PAIMON-icon.svg"),atomically:true,encoding:.utf8)
try (svgHeader+symbol+"</svg>\n").write(to:brand.appendingPathComponent("PAIMON-symbol.svg"),atomically:true,encoding:.utf8)
let cover=try bitmap(width:1600,height:600) { c in
    c.setFillColor(navy.cgColor); c.fill(CGRect(x:0,y:0,width:1600,height:600))
    c.saveGState(); c.translateBy(x:1000,y:10); c.scaleBy(x:0.56,y:0.56); sigil(c); c.restoreGState()
    func text(_ text:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:NSColor,_ weight:NSFont.Weight) {
        // AppKit text drawing uses an unflipped graphics context.
        c.saveGState(); c.translateBy(x:0,y:600); c.scaleBy(x:1,y:-1)
        (text as NSString).draw(at:CGPoint(x:x,y:600-y-size*1.2),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color]); c.restoreGState()
    }
    text("PAIMON",104,154,82,ivory,.semibold)
    text("LOCAL AUDIO INTELLIGENCE",109,264,22,muted,.medium)
    text("Transformando sonido",107,330,39,ivory,.regular)
    text("en conocimiento.",107,380,39,ivory,.regular)
    text("macOS · Apple Silicon · Audio local",109,500,20,muted,.regular)
}
try cover.write(to:root.appendingPathComponent("docs/images/paimon-cover.png"))
print("PAIMON: SVG, icono 1024 y portada 1600 × 600 generados.")
