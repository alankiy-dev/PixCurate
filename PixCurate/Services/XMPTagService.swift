import Foundation

enum XMPTagService {

    nonisolated static func readTags(xmpURL: URL) -> [String] {
        guard let content = try? String(contentsOf: xmpURL, encoding: .utf8) else { return [] }
        return parseTags(from: content)
    }

    nonisolated private static func parseTags(from content: String) -> [String] {
        guard let bagRegex = try? NSRegularExpression(
            pattern: #"<dc:subject>\s*<rdf:Bag>(.*?)</rdf:Bag>\s*</dc:subject>"#,
            options: [.dotMatchesLineSeparators]
        ) else { return [] }

        let nsRange = NSRange(content.startIndex..., in: content)
        guard let match = bagRegex.firstMatch(in: content, range: nsRange),
              let bagRange = Range(match.range(at: 1), in: content) else { return [] }

        let bagContent = String(content[bagRange])
        guard let liRegex = try? NSRegularExpression(pattern: #"<rdf:li>(.*?)</rdf:li>"#) else { return [] }

        let liNSRange = NSRange(bagContent.startIndex..., in: bagContent)
        return liRegex.matches(in: bagContent, range: liNSRange).compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: bagContent) else { return nil }
            let t = String(bagContent[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
    }

    nonisolated static func writeTags(to xmpURL: URL, tags: [String]) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: xmpURL.path) {
            let content = makeMinimalXMP(tags: tags)
            return (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
        }

        guard var content = try? String(contentsOf: xmpURL, encoding: .utf8) else { return false }
        let newBlock = makeTagBlock(tags: tags)

        // Replace existing dc:subject block
        if let regex = try? NSRegularExpression(
            pattern: #"<dc:subject>\s*<rdf:Bag>.*?</rdf:Bag>\s*</dc:subject>"#,
            options: [.dotMatchesLineSeparators]
        ) {
            let nsRange = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, range: nsRange) != nil {
                content = regex.stringByReplacingMatches(in: content, range: nsRange, withTemplate: newBlock)
                return (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
            }
        }

        // Insert before </rdf:Description>
        if content.contains("</rdf:Description>") {
            content = content.replacingOccurrences(
                of: "</rdf:Description>",
                with: "  \(newBlock)\n  </rdf:Description>"
            )
            return (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
        }
        return false
    }

    nonisolated private static func makeTagBlock(tags: [String]) -> String {
        guard !tags.isEmpty else { return "<dc:subject><rdf:Bag/></dc:subject>" }
        let items = tags.map { "      <rdf:li>\($0)</rdf:li>" }.joined(separator: "\n")
        return "<dc:subject>\n     <rdf:Bag>\n\(items)\n     </rdf:Bag>\n    </dc:subject>"
    }

    nonisolated private static func makeMinimalXMP(tags: [String]) -> String {
        """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:dc="http://purl.org/dc/elements/1.1/">
           \(makeTagBlock(tags: tags))
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
}
