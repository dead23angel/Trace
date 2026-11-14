// Builds the animated tour shown at the top of the README from screenshots.
//
//   swift scripts/make-gif.swift <output.gif> <frame.png> [<frame.png> ...]
//
// Each screenshot is held for a moment and cross-faded into the next.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else {
    print("usage: make-gif.swift <output.gif> <frame.png> <frame.png> ...")
    exit(1)
}
let width = 1100
let hold = 2.2, fadeSteps = 4, fadeDelay = 0.07

func load(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("cannot read \(path)")
        exit(1)
    }
    return image
}

let sources = args.dropFirst().map(load)
let height = Int((Double(width) * Double(sources[0].height) / Double(sources[0].width)).rounded())
let rect = CGRect(x: 0, y: 0, width: width, height: height)

/// `from` with `to` drawn over it at `alpha`, on white, at the output size.
func frame(_ from: CGImage, over to: CGImage? = nil, alpha: CGFloat = 0) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(rect)
    ctx.draw(from, in: rect)
    if let to {
        ctx.setAlpha(alpha)
        ctx.draw(to, in: rect)
    }
    return ctx.makeImage()!
}

var frames: [(CGImage, Double)] = []
for (index, image) in sources.enumerated() {
    frames.append((frame(image), hold))
    let next = sources[(index + 1) % sources.count]
    for step in 1...fadeSteps {
        frames.append((frame(image, over: next, alpha: CGFloat(step) / CGFloat(fadeSteps + 1)), fadeDelay))
    }
}

let url = URL(fileURLWithPath: args[0])
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
    print("cannot write \(args[0])")
    exit(1)
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (image, delay) in frames {
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay,
    ]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else {
    print("could not finish \(args[0])")
    exit(1)
}
print("\(args[0]): \(frames.count) frames, \(width)x\(height)")
