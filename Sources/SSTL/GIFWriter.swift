import Foundation

struct GIFOptions: Equatable {
    var maxSide = 720      // longest side in pixels
    var colors = 256       // colour table size: 64, 128 or 256 (one entry is kept for "unchanged")
    var dither = false     // ordered dithering: smoother gradients, larger files
}

// Colour reduction: a palette picked from sample frames, then a lookup table for fast nearest-colour mapping.
enum GIFQuantizer {
    // Counts and exact colour sums per 5-bit-per-channel cell, so palette entries are true averages.
    final class Histogram {
        var count = [UInt32](repeating: 0, count: 32768)
        var sum = [UInt64](repeating: 0, count: 32768 * 3)

        // `bgra` is 4 bytes per pixel (blue, green, red, unused); every `step`th pixel is counted.
        func add(_ bgra: [UInt8], every step: Int) {
            bgra.withUnsafeBufferPointer { p in
                var i = 0
                let n = p.count / 4
                while i < n {
                    let b = Int(p[i * 4]), g = Int(p[i * 4 + 1]), r = Int(p[i * 4 + 2])
                    let cell = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
                    count[cell] += 1
                    sum[cell * 3] += UInt64(r)
                    sum[cell * 3 + 1] += UInt64(g)
                    sum[cell * 3 + 2] += UInt64(b)
                    i += step
                }
            }
        }
    }

    private struct Cell {
        var r: Int, g: Int, b: Int
        var count: Int
        var sr: Int, sg: Int, sb: Int
    }

    // Median cut: repeatedly split the box holding the most pixels at its weighted median along its longest side.
    // Returns RGB triples, at most `colors` of them.
    static func palette(_ histogram: Histogram, colors: Int) -> [UInt8] {
        var cells: [Cell] = []
        for i in 0..<32768 where histogram.count[i] > 0 {
            cells.append(Cell(r: i >> 10, g: (i >> 5) & 31, b: i & 31, count: Int(histogram.count[i]),
                              sr: Int(histogram.sum[i * 3]), sg: Int(histogram.sum[i * 3 + 1]), sb: Int(histogram.sum[i * 3 + 2])))
        }
        guard !cells.isEmpty else { return [0, 0, 0] }
        var boxes: [Range<Int>] = [0..<cells.count]
        while boxes.count < colors {
            var best = -1, bestPopulation = 0
            for (k, box) in boxes.enumerated() where box.count > 1 {
                let population = cells[box].reduce(0) { $0 + $1.count }
                if population > bestPopulation { bestPopulation = population; best = k }
            }
            if best < 0 { break }
            let box = boxes[best]
            var low = (r: 31, g: 31, b: 31), high = (r: 0, g: 0, b: 0)
            for cell in cells[box] {
                low = (min(low.r, cell.r), min(low.g, cell.g), min(low.b, cell.b))
                high = (max(high.r, cell.r), max(high.g, cell.g), max(high.b, cell.b))
            }
            let spans = (r: high.r - low.r, g: high.g - low.g, b: high.b - low.b)
            if spans.r >= spans.g, spans.r >= spans.b {
                cells[box].sort { $0.r < $1.r }
            } else if spans.g >= spans.b {
                cells[box].sort { $0.g < $1.g }
            } else {
                cells[box].sort { $0.b < $1.b }
            }
            var running = 0
            var cut = box.lowerBound + 1
            for i in box {
                running += cells[i].count
                if running * 2 >= bestPopulation {
                    cut = min(max(i + 1, box.lowerBound + 1), box.upperBound - 1)
                    break
                }
            }
            boxes[best] = box.lowerBound..<cut
            boxes.append(cut..<box.upperBound)
        }
        return boxes.flatMap { box -> [UInt8] in
            var count = 0, r = 0, g = 0, b = 0
            for cell in cells[box] { count += cell.count; r += cell.sr; g += cell.sg; b += cell.sb }
            return [UInt8(r / count), UInt8(g / count), UInt8(b / count)]
        }
    }

    // Nearest palette entry for every colour at 6 bits per channel: index = r6 << 12 | g6 << 6 | b6.
    static func lookup(for palette: [UInt8]) -> [UInt8] {
        let entries = palette.count / 3
        var table = [UInt8](repeating: 0, count: 64 * 64 * 64)
        table.withUnsafeMutableBufferPointer { out in
            let base = out.baseAddress!
            palette.withUnsafeBufferPointer { p in
                DispatchQueue.concurrentPerform(iterations: 64) { r in
                    let cr = r * 4 + 2
                    for g in 0..<64 {
                        let cg = g * 4 + 2
                        for b in 0..<64 {
                            let cb = b * 4 + 2
                            var best = 0, bestDistance = Int.max
                            for k in 0..<entries {
                                let dr = cr - Int(p[k * 3]), dg = cg - Int(p[k * 3 + 1]), db = cb - Int(p[k * 3 + 2])
                                let distance = dr * dr + dg * dg + db * db
                                if distance < bestDistance { bestDistance = distance; best = k }
                            }
                            base[r << 12 | g << 6 | b] = UInt8(best)
                        }
                    }
                }
            }
        }
        return table
    }

    // BGRA pixels to palette indices. Ordered dithering gives the same result for the same pixel in every frame,
    // so still areas stay still and compress away.
    static func indices(bgra: [UInt8], width: Int, height: Int, lookup: [UInt8], dither: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        // 4x4 Bayer matrix turned into per-position colour offsets.
        let matrix: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { (($0 * 2 - 15) * dither) >> 4 }
        bgra.withUnsafeBufferPointer { p in
            lookup.withUnsafeBufferPointer { lut in
                matrix.withUnsafeBufferPointer { offsets in
                    out.withUnsafeMutableBufferPointer { o in
                        for y in 0..<height {
                            let row = y * width
                            if dither == 0 {
                                for x in 0..<width {
                                    let i = row + x
                                    o[i] = lut[(Int(p[i * 4 + 2]) >> 2) << 12 | (Int(p[i * 4 + 1]) >> 2) << 6 | (Int(p[i * 4]) >> 2)]
                                }
                            } else {
                                for x in 0..<width {
                                    let i = row + x
                                    let offset = offsets[(y & 3) * 4 + (x & 3)]
                                    let r = min(255, max(0, Int(p[i * 4 + 2]) + offset))
                                    let g = min(255, max(0, Int(p[i * 4 + 1]) + offset))
                                    let b = min(255, max(0, Int(p[i * 4]) + offset))
                                    o[i] = lut[(r >> 2) << 12 | (g >> 2) << 6 | (b >> 2)]
                                }
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}

// Streaming GIF89a writer: each frame is cut down to the rectangle that changed since the previous one,
// compressed, and written straight to disk, so memory use does not grow with the number of frames.
final class GIFWriter {
    private let handle: FileHandle
    private let width: Int
    private let height: Int
    private let tableBits: Int
    private let transparent: Int
    private var previous: [UInt8]?
    private var codes = [UInt16](repeating: 0, count: 4096 * 256)

    // `palette` is RGB triples; `tableSize` (a power of two from 4 to 256) leaves its last entry for "unchanged".
    init(url: URL, width: Int, height: Int, palette: [UInt8], tableSize: Int, loop: Int = 0) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        self.width = width
        self.height = height
        tableBits = max(2, Int(log2(Double(tableSize)).rounded()))
        transparent = (1 << tableBits) - 1
        var header: [UInt8] = Array("GIF89a".utf8)
        header += le(width)
        header += le(height)
        header += [0x80 | 0x70 | UInt8(tableBits - 1), 0, 0]
        var table = palette
        table += [UInt8](repeating: 0, count: (1 << tableBits) * 3 - table.count)
        header += table
        header += [0x21, 0xFF, 0x0B]
        header += Array("NETSCAPE2.0".utf8)
        header += [0x03, 0x01]
        header += le(loop)
        header.append(0x00)
        try handle.write(contentsOf: Data(header))
    }

    private func le(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }

    // `indices` is width x height palette indices; `delay` is in hundredths of a second.
    func add(indices: [UInt8], delay: Int) throws {
        var x = 0, y = 0, w = width, h = height
        var pixels = indices
        if let previous {
            var minX = width, minY = height, maxX = -1, maxY = -1
            indices.withUnsafeBufferPointer { now in
                previous.withUnsafeBufferPointer { before in
                    for row in 0..<height {
                        let start = row * width
                        var column = 0
                        while column < width, now[start + column] == before[start + column] { column += 1 }
                        if column == width { continue }
                        var last = width - 1
                        while now[start + last] == before[start + last] { last -= 1 }
                        minX = min(minX, column); maxX = max(maxX, last)
                        minY = min(minY, row); maxY = max(maxY, row)
                    }
                }
            }
            if maxX < 0 {
                (x, y, w, h) = (0, 0, 1, 1)
                pixels = [UInt8(transparent)]
            } else {
                (x, y, w, h) = (minX, minY, maxX - minX + 1, maxY - minY + 1)
                pixels = [UInt8](repeating: 0, count: w * h)
                for row in 0..<h {
                    for column in 0..<w {
                        let source = (y + row) * width + x + column
                        pixels[row * w + column] = indices[source] == previous[source] ? UInt8(transparent) : indices[source]
                    }
                }
            }
        }
        var frame: [UInt8] = [0x21, 0xF9, 0x04, previous == nil ? 0x04 : 0x05]
        frame += le(max(2, delay))
        frame += [UInt8(transparent), 0x00, 0x2C]
        frame += le(x)
        frame += le(y)
        frame += le(w)
        frame += le(h)
        frame.append(0x00)
        frame.append(UInt8(tableBits))
        let stream = compress(pixels)
        var offset = 0
        while offset < stream.count {
            let size = min(255, stream.count - offset)
            frame.append(UInt8(size))
            frame += stream[offset..<offset + size]
            offset += size
        }
        frame.append(0x00)
        try handle.write(contentsOf: Data(frame))
        previous = indices
    }

    func finish() throws {
        try handle.write(contentsOf: Data([0x3B]))
        try handle.close()
    }

    // Variable-width LZW as used by GIF.
    private func compress(_ pixels: [UInt8]) -> [UInt8] {
        let clear = 1 << tableBits, end = clear + 1
        var out: [UInt8] = []
        out.reserveCapacity(pixels.count / 2 + 16)
        var buffer: UInt32 = 0, bits = 0
        var codeBits = tableBits + 1, limit = 1 << codeBits, nextCode = end + 1

        func emit(_ code: Int) {
            buffer |= UInt32(code) << UInt32(bits)
            bits += codeBits
            while bits >= 8 {
                out.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                bits -= 8
            }
            if code == clear {
                codeBits = tableBits + 1; limit = 1 << codeBits; nextCode = end + 1
            } else if nextCode >= limit, code <= 4095 {
                codeBits += 1; limit = 1 << codeBits
            }
        }
        func resetTable() { codes.withUnsafeMutableBytes { _ = memset($0.baseAddress!, 0, $0.count) } }

        resetTable()
        emit(clear)
        var prefix = Int(pixels[0])
        for i in 1..<pixels.count {
            let pixel = Int(pixels[i])
            let child = Int(codes[prefix << 8 | pixel])
            if child != 0 {
                prefix = child
                continue
            }
            emit(prefix)
            if nextCode >= 4095 {
                emit(clear)
                resetTable()
            } else {
                codes[prefix << 8 | pixel] = UInt16(nextCode)
                nextCode += 1
            }
            prefix = pixel
        }
        emit(prefix)
        emit(end)
        if bits > 0 { out.append(UInt8(buffer & 0xFF)) }
        return out
    }
}
