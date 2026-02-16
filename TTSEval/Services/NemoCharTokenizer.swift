import Foundation

/// Char-only tokenizer for NeMo FastPitch, aligned with the Android implementation:
/// - ASCII upper -> lower
/// - unsupported chars mapped to space
/// - repeated spaces collapsed and trimmed
/// - optional blank token inserted between every symbol
struct NemoCharTokenizer: Sendable {
    let symbolToId: [String: Int64]
    let blankId: Int64
    let padId: Int64
    let addBlank: Bool

    func tokenize(_ text: String) -> [Int64] {
        let spaceId = symbolToId[" "] ?? padId

        var tokenIds: [Int64] = []
        tokenIds.reserveCapacity(text.count)

        var lastWasSpace = true

        for raw in text {
            let rawS = String(raw)
            let normalized: String = {
                if rawS == "\n" || rawS == "\t" || rawS == "\r" {
                    return " "
                }
                // ASCII uppercasing only (NeMo FastPitch symbols are typically ASCII).
                let scalars = rawS.unicodeScalars
                if scalars.count == 1, let v = scalars.first?.value, v >= 65 && v <= 90, let lower = UnicodeScalar(v + 32) {
                    return String(Character(lower))
                }
                return rawS
            }()

            let id = symbolToId[normalized] ?? spaceId
            let isSpace = id == spaceId

            if isSpace {
                if lastWasSpace { continue }
                lastWasSpace = true
                tokenIds.append(spaceId)
            } else {
                lastWasSpace = false
                tokenIds.append(id)
            }
        }

        if tokenIds.count > 1, tokenIds.last == spaceId {
            tokenIds.removeLast()
        }

        if tokenIds.isEmpty {
            tokenIds.append(spaceId)
        }

        if !addBlank || tokenIds.count == 1 {
            return tokenIds
        }

        var out: [Int64] = []
        out.reserveCapacity(tokenIds.count * 2 - 1)
        for i in tokenIds.indices {
            out.append(tokenIds[i])
            if i != tokenIds.indices.last {
                out.append(blankId)
            }
        }
        return out
    }
}
