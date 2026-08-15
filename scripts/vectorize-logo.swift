import CoreGraphics
import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: vectorize-logo.swift input.png output.svg\n".utf8))
    exit(64)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Could not read \(input.path)")
}

let request = VNDetectContoursRequest()
request.contrastAdjustment = 1
request.detectsDarkOnLight = true
request.maximumImageDimension = 1024
let handler = VNImageRequestHandler(cgImage: image)
try handler.perform([request])
guard let observation = request.results?.first else {
    fatalError("No contours found")
}

func number(_ value: CGFloat) -> String {
    var result = String(format: "%.5f", Double(value))
    while result.contains(".") && result.last == "0" { result.removeLast() }
    if result.last == "." { result.removeLast() }
    return result
}

func commands(for path: CGPath) -> String {
    var result: [String] = []
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        switch element.type {
        case .moveToPoint:
            result.append("M\(number(element.points[0].x)) \(number(element.points[0].y))")
        case .addLineToPoint:
            result.append("L\(number(element.points[0].x)) \(number(element.points[0].y))")
        case .addQuadCurveToPoint:
            result.append(
                "Q\(number(element.points[0].x)) \(number(element.points[0].y)) "
                    + "\(number(element.points[1].x)) \(number(element.points[1].y))"
            )
        case .addCurveToPoint:
            result.append(
                "C\(number(element.points[0].x)) \(number(element.points[0].y)) "
                    + "\(number(element.points[1].x)) \(number(element.points[1].y)) "
                    + "\(number(element.points[2].x)) \(number(element.points[2].y))"
            )
        case .closeSubpath:
            result.append("Z")
        @unknown default:
            break
        }
    }
    return result.joined(separator: " ")
}

func collect(_ contour: VNContour, into paths: inout [String]) throws {
    let simplified = try contour.polygonApproximation(epsilon: 0.0015)
    paths.append(commands(for: simplified.normalizedPath))
    for child in contour.childContours {
        try collect(child, into: &paths)
    }
}

var paths: [String] = []
for contour in observation.topLevelContours {
    try collect(contour, into: &paths)
}

let pathData = paths.joined(separator: " ")
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">Catway</title>
  <desc id="desc">A clean black and white cat in side profile.</desc>
  <rect width="1024" height="1024" fill="#fff"/>
  <path d="\(pathData)" transform="translate(0 1024) scale(1024 -1024)" fill="#000" fill-rule="evenodd"/>
</svg>
"""
try Data(svg.utf8).write(to: output, options: .atomic)
