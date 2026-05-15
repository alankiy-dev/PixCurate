import Foundation

enum XMPService {

    // MARK: - XMP直接読み取り（exiftool不要・サンドボックス対応）

    /// XMPサイドカーから★評価を直接テキスト解析で読み取る
    nonisolated static func readRating(xmpURL: URL) -> Int? {
        guard let content = try? String(contentsOf: xmpURL, encoding: .utf8) else { return nil }

        // 属性形式: xmp:Rating="3"（Adobe Bridge/Lightroom/Camera Raw の標準形式）
        if let rating = extractRating(from: content, pattern: #"xmp:Rating="(\d+)""#) {
            return rating
        }
        // 要素形式: <xmp:Rating>3</xmp:Rating>
        if let rating = extractRating(from: content, pattern: #"<xmp:Rating>(\d+)</xmp:Rating>"#) {
            return rating
        }
        return nil
    }

    nonisolated private static func extractRating(from content: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content),
              let rating = Int(content[range]),
              rating > 0
        else { return nil }
        return rating
    }

    // MARK: - XMP直接書き込み（サンドボックス対応）

    nonisolated static func writeRating(to xmpURL: URL, rating: Int) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: xmpURL.path) {
            let content = makeMinimalXMP(rating: rating)
            return (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
        }

        guard var content = try? String(contentsOf: xmpURL, encoding: .utf8) else { return false }

        // 属性形式を置換
        if let regex = try? NSRegularExpression(pattern: #"xmp:Rating="(\d+)""#) {
            let ns = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, range: ns) != nil {
                content = regex.stringByReplacingMatches(
                    in: content, range: ns,
                    withTemplate: #"xmp:Rating="\#(rating)""#
                )
                return (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
            }
        }

        // 要素形式を置換
        if let regex = try? NSRegularExpression(pattern: #"<xmp:Rating>\d+</xmp:Rating>"#) {
            let ns = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, range: ns) != nil {
                content = regex.stringByReplacingMatches(
                    in: content, range: ns,
                    withTemplate: "<xmp:Rating>\(rating)</xmp:Rating>"
                )
                return (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
            }
        }

        // xmp名前空間を追加しつつ挿入
        if content.contains("xmlns:xmp=") {
            content = content.replacingOccurrences(
                of: "</rdf:Description>",
                with: "  xmp:Rating=\"\(rating)\"\n  </rdf:Description>",
                range: content.range(of: "</rdf:Description>")
            )
        } else {
            content = content.replacingOccurrences(
                of: "<rdf:Description ",
                with: "<rdf:Description xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmp:Rating=\"\(rating)\" ",
                range: content.range(of: "<rdf:Description ")
            )
        }
        return (try? content.write(to: xmpURL, atomically: true, encoding: .utf8)) != nil
    }

    nonisolated private static func makeMinimalXMP(rating: Int) -> String {
        """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmp:Rating="\(rating)"/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
}
