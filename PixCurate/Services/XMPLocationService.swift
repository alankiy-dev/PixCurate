import Foundation

// Maps to IPTC Core XMP fields (Lightroom/Bridge compatible)
struct LocationPath: Sendable, Equatable {
    var province: String?     // Iptc4xmpCore:ProvinceState  (都道府県)
    var city: String?         // Iptc4xmpCore:City            (市区町村)
    var sublocation: String?  // Iptc4xmpCore:SubLocation     (撮影場所)

    var isEmpty: Bool { province == nil && city == nil && sublocation == nil }
}

enum XMPLocationService {

    nonisolated static func readLocation(xmpURL: URL) -> LocationPath? {
        guard let content = try? String(contentsOf: xmpURL, encoding: .utf8) else { return nil }
        let province    = extract(tag: "Iptc4xmpCore:ProvinceState", from: content)
        let city        = extract(tag: "Iptc4xmpCore:City",          from: content)
        let sublocation = extract(tag: "Iptc4xmpCore:SubLocation",   from: content)
        guard province != nil || city != nil || sublocation != nil else { return nil }
        return LocationPath(province: province, city: city, sublocation: sublocation)
    }

    nonisolated static func writeLocation(to xmpURL: URL, path: LocationPath) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: xmpURL.path) {
            return (try? makeMinimalXMP(path: path).write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
        }
        guard var content = try? String(contentsOf: xmpURL, encoding: .utf8) else { return false }

        // Ensure IPTC Core namespace is declared
        content = ensureNamespace(in: content)

        // Set or replace each IPTC field
        content = setField("Iptc4xmpCore:ProvinceState", value: path.province, in: content)
        content = setField("Iptc4xmpCore:City",          value: path.city,     in: content)
        content = setField("Iptc4xmpCore:SubLocation",   value: path.sublocation, in: content)

        return (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
    }

    // MARK: - Private helpers

    nonisolated private static func extract(tag: String, from content: String) -> String? {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let r = Range(match.range(at: 1), in: content) else { return nil }
        let val = String(content[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return val.isEmpty ? nil : val
    }

    nonisolated private static func ensureNamespace(in content: String) -> String {
        let ns = #"xmlns:Iptc4xmpCore="http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/""#
        guard !content.contains("Iptc4xmpCore") else { return content }
        return content.replacingOccurrences(
            of: "rdf:about=\"\"",
            with: "rdf:about=\"\"\n    \(ns)"
        )
    }

    nonisolated private static func setField(_ tag: String, value: String?, in content: String) -> String {
        let pattern = "<\(tag)>.*?</\(tag)>"
        let replacement = value.map { "<\(tag)>\($0)</\(tag)>" } ?? ""

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let nsRange = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, range: nsRange) != nil {
                return regex.stringByReplacingMatches(in: content, range: nsRange, withTemplate: replacement)
            }
        }
        // Field not present yet — insert before </rdf:Description>
        guard let value else { return content }
        return content.replacingOccurrences(
            of: "</rdf:Description>",
            with: "  <\(tag)>\(value)</\(tag)>\n  </rdf:Description>"
        )
    }

    nonisolated private static func makeMinimalXMP(path: LocationPath) -> String {
        var fields = ""
        if let v = path.province    { fields += "   <Iptc4xmpCore:ProvinceState>\(v)</Iptc4xmpCore:ProvinceState>\n" }
        if let v = path.city        { fields += "   <Iptc4xmpCore:City>\(v)</Iptc4xmpCore:City>\n" }
        if let v = path.sublocation { fields += "   <Iptc4xmpCore:SubLocation>\(v)</Iptc4xmpCore:SubLocation>\n" }
        return """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:Iptc4xmpCore="http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/">
        \(fields)  </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
}
