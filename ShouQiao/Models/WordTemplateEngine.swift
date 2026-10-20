import Foundation

struct WordCandidate: Identifiable, Hashable {
    let id: String
    let label: String
    let distance: Double
}

/// Loads the same 22-word, 18-frame, 108-feature templates as Android 2.0.
final class WordTemplateEngine {
    private struct Template {
        let id: String
        let label: String
        let frames: [[Float]]
    }

    private static let frameCount = 18
    private static let featureCount = 108
    private static let band = 5

    private static let weights: [Float] = {
        var values = [Float](repeating: 0.8, count: 22)
        values.append(contentsOf: [Float](repeating: 1.0, count: 84))
        values.append(contentsOf: [Float](repeating: 3.0, count: 2))
        return values
    }()

    private var templates: [Template] = []
    private(set) var loadError: String?

    init() {
        guard let url = Bundle.main.url(
            forResource: "word_templates",
            withExtension: "bin"
        ) else {
            loadError = "word_templates.bin 未加入 App Bundle"
            return
        }
        do {
            templates = try Self.read(url: url)
        } catch {
            loadError = error.localizedDescription
        }
    }

    var labels: [String] {
        templates.map(\.label)
    }

    func match(_ observed: [[Float]], limit: Int = 3) -> [WordCandidate] {
        guard observed.count >= 2, !templates.isEmpty else { return [] }
        let resampled = Self.resample(observed, to: Self.frameCount)
        return templates
            .map { template in
                WordCandidate(
                    id: template.id,
                    label: template.label,
                    distance: Self.distance(resampled, template.frames)
                )
            }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }

    private static func read(url: URL) throws -> [Template] {
        let reader = BigEndianReader(data: try Data(contentsOf: url))
        let magic = try reader.u32()
        guard magic == 0x53425631 else {
            throw NSError(domain: "ShouQiao.WordTemplates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "词库格式不匹配"])
        }
        let count = Int(try reader.u32())
        let frames = Int(try reader.u32())
        let features = Int(try reader.u32())
        guard frames == frameCount, features == featureCount else {
            throw NSError(domain: "ShouQiao.WordTemplates", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "词库尺寸不匹配"])
        }

        var result: [Template] = []
        for _ in 0..<count {
            let id = try reader.string()
            let label = try reader.string()
            var sequence: [[Float]] = []
            sequence.reserveCapacity(frames)
            for _ in 0..<frames {
                var frame: [Float] = []
                frame.reserveCapacity(features)
                for _ in 0..<features {
                    frame.append(try reader.float())
                }
                sequence.append(frame)
            }
            result.append(Template(id: id, label: label, frames: sequence))
        }
        return result
    }

    private static func resample(_ source: [[Float]], to count: Int) -> [[Float]] {
        guard let first = source.first, source.count >= 2 else { return [] }
        var result: [[Float]] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let position = Double(i) * Double(source.count - 1) / Double(count - 1)
            let lower = Int(floor(position))
            let upper = min(lower + 1, source.count - 1)
            let fraction = Float(position - Double(lower))
            let a = source[lower]
            let b = source[upper]
            let n = min(first.count, min(a.count, b.count))
            var frame = [Float](repeating: 0, count: n)
            for j in 0..<n {
                frame[j] = a[j] * (1 - fraction) + b[j] * fraction
            }
            result.append(frame)
        }
        return result
    }

    private static func distance(_ left: [[Float]], _ right: [[Float]]) -> Double {
        guard !left.isEmpty, !right.isEmpty,
              left[0].count == featureCount,
              right[0].count == featureCount else {
            return .infinity
        }
        let n = left.count
        let m = right.count
        var prior = [Float](repeating: .infinity, count: m + 1)
        prior[0] = 0

        for i in 1...n {
            var current = [Float](repeating: .infinity, count: m + 1)
            let center = Int((Double(i) * Double(m) / Double(n)).rounded())
            let lower = max(1, center - band)
            let upper = min(m, center + band)
            if lower > upper { continue }
            for j in lower...upper {
                var sum: Float = 0
                for k in 0..<featureCount {
                    let delta = left[i - 1][k] - right[j - 1][k]
                    sum += weights[k] * delta * delta
                }
                let cost = sqrt(sum / Float(featureCount))
                current[j] = cost + min(prior[j], min(prior[j - 1], current[j - 1]))
            }
            prior = current
        }
        return Double(prior[m] / Float(max(n, m)))
    }
}

private final class BigEndianReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    func u16() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw readError() }
        let value = data[offset..<offset + 2].reduce(UInt16(0)) {
            ($0 << 8) | UInt16($1)
        }
        offset += 2
        return value
    }

    func u32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw readError() }
        let value = data[offset..<offset + 4].reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        offset += 4
        return value
    }

    func float() throws -> Float {
        Float(bitPattern: try u32())
    }

    func string() throws -> String {
        let count = Int(try u16())
        guard offset + count <= data.count else { throw readError() }
        let value = String(data: data[offset..<offset + count], encoding: .utf8) ?? ""
        offset += count
        return value
    }

    private func readError() -> NSError {
        NSError(domain: "ShouQiao.WordTemplates", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "词库数据不完整"])
    }
}
