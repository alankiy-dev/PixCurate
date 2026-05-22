import Foundation

// MARK: - XLSXThumbnail

/// XLSX に埋め込むサムネイル（JPEG データ＋実際のピクセルサイズ）
struct XLSXThumbnail {
    let data:   Data
    let width:  Int   // px
    let height: Int   // px
}

// MARK: - XLSX Exporter
// xlsx = ZIP(XML群) をライブラリなしで生成する。
// スタイル: ヘッダー行 = 青背景・白太字・罫線、データ行 = 罫線のみ
// thumbnails を渡すと列 A に JPEG 画像を埋め込む（行高さ自動設定）

enum XLSXExporter {

    // MARK: - Public

    /// - columnWidths: 各列の幅（文字単位）。nil の場合はデフォルト幅を使用
    /// - thumbnails:   行ごとのサムネイル（nil = 画像なし）。非 nil の場合サムネイル列を先頭に追加
    static func write(headers: [String], rows: [[String]],
                      columnWidths: [Double]? = nil,
                      thumbnails: [XLSXThumbnail?]? = nil,
                      to url: URL) throws {
        let data = buildXLSX(headers: headers, rows: rows,
                              columnWidths: columnWidths, thumbnails: thumbnails)
        try data.write(to: url)
    }

    // MARK: - Build

    private static func buildXLSX(headers: [String], rows: [[String]],
                                   columnWidths: [Double]? = nil,
                                   thumbnails: [XLSXThumbnail?]? = nil) -> Data {
        // ── 画像エントリを構築 ──────────────────────────────────────
        var imageEntries: [ImageEntry] = []
        if let thumbs = thumbnails {
            var rIdx = 1
            for (ri, thumb) in thumbs.enumerated() {
                if let t = thumb {
                    // 行高さ = ceil(height_px × 0.75) + 20pt マージン（上下各 10pt）
                    let ht = (Double(t.height) * 0.75).rounded(.up) + 20
                    imageEntries.append(ImageEntry(
                        rowIndex: ri, rId: "rId\(rIdx)", filename: "image\(rIdx).jpg",
                        width: t.width, height: t.height, rowHtPt: ht
                    ))
                    rIdx += 1
                }
            }
        }
        let hasImages = !imageEntries.isEmpty

        // ── サムネイル列を先頭に追加（画像がある場合のみ） ────────────
        let allHeaders = hasImages ? ["サムネイル"] + headers : headers
        let allRows    = hasImages ? rows.map { [""] + $0 } : rows

        // 列幅（サムネイル列 = 22 chars ≈ 154px、画像 120px + 左右各 17px マージン）
        let allWidths: [Double]? = {
            guard hasImages else { return columnWidths }
            if let w = columnWidths { return [22.0] + w }
            return nil          // worksheetXML がデフォルト生成
        }()

        // ── 共有文字列テーブル ─────────────────────────────────────
        var strings: [String] = []
        var strIdx:  [String: Int] = [:]
        func si(_ s: String) -> Int {
            if let i = strIdx[s] { return i }
            let i = strings.count; strings.append(s); strIdx[s] = i; return i
        }
        for h in allHeaders { _ = si(h) }
        for row in allRows  { for c in row { _ = si(c) } }

        // ── ヘッダー行（style=2: 青背景・白太字・罫線） ──────────────
        let headerRow: String = {
            let cells = allHeaders.enumerated().map { (col, h) in
                "<c r=\"\(xlCol(col))1\" t=\"s\" s=\"2\"><v>\(si(h))</v></c>"
            }.joined()
            return "<row r=\"1\">\(cells)</row>"
        }()

        // ── データ行（style=1: 罫線）──────────────────────────────────
        // 画像あり時: imageEntries が持つ rowHtPt をそのまま使う
        // 画像のない行（オフライン等）は画像行の最大高さに揃える
        let rowHeightMap: [Int: Double] = Dictionary(
            uniqueKeysWithValues: imageEntries.map { ($0.rowIndex, $0.rowHtPt) }
        )
        let maxRowHeight: Double = rowHeightMap.values.max() ?? 68

        let dataRows: String = allRows.enumerated().map { (ri, row) in
            let r = ri + 2
            let htAttr: String = {
                guard hasImages else { return "" }
                let ht = rowHeightMap[ri] ?? maxRowHeight
                return " ht=\"\(ht)\" customHeight=\"1\""
            }()
            let cells = row.enumerated().map { (col, val) in
                val.isEmpty
                    ? "<c r=\"\(xlCol(col))\(r)\" s=\"1\"/>"
                    : "<c r=\"\(xlCol(col))\(r)\" t=\"s\" s=\"1\"><v>\(si(val))</v></c>"
            }.joined()
            return "<row r=\"\(r)\"\(htAttr)>\(cells)</row>"
        }.joined()

        let lastCol  = xlCol(max(allHeaders.count - 1, 0))
        let lastRow  = rows.count + 1
        let dim      = "A1:\(lastCol)\(lastRow)"
        let colCount = allHeaders.count

        // ── XML ファイル群 ─────────────────────────────────────────
        var xmlFiles: [(String, Data)] = [
            ("[Content_Types].xml",
             Data(contentTypesXML(hasImages: hasImages).utf8)),
            ("_rels/.rels",
             Data(relsXML.utf8)),
            ("xl/workbook.xml",
             Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels",
             Data(workbookRelsXML.utf8)),
            ("xl/styles.xml",
             Data(stylesXML.utf8)),
            ("xl/sharedStrings.xml",
             Data(sharedStringsXML(strings).utf8)),
            ("xl/worksheets/sheet1.xml",
             Data(worksheetXML(dim: dim, colCount: colCount,
                               columnWidths: allWidths,
                               rows: headerRow + dataRows,
                               hasDrawing: hasImages).utf8)),
        ]

        if hasImages, let thumbs = thumbnails {
            // メディアファイル（JPEG）
            var mIdx = 1
            for thumb in thumbs {
                if let t = thumb {
                    xmlFiles.append(("xl/media/image\(mIdx).jpg", t.data))
                    mIdx += 1
                }
            }
            // 描画 XML
            xmlFiles.append(("xl/drawings/drawing1.xml",
                              Data(drawingXML(imageEntries: imageEntries).utf8)))
            xmlFiles.append(("xl/drawings/_rels/drawing1.xml.rels",
                              Data(drawingRelsXML(imageEntries: imageEntries).utf8)))
            // シート → 描画リレーション
            xmlFiles.append(("xl/worksheets/_rels/sheet1.xml.rels",
                              Data(sheetRelsForDrawingXML.utf8)))
        }

        let entries = xmlFiles.map { ZIPEntry(filename: $0.0, data: $0.1) }
        return ZIPWriter.archive(entries)
    }

    // MARK: - Column letter (0=A, 25=Z, 26=AA …)

    private static func xlCol(_ col: Int) -> String {
        var n = col, result = ""
        repeat {
            result = String(UnicodeScalar(65 + n % 26)!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    // MARK: - ImageEntry

    private struct ImageEntry {
        let rowIndex: Int      // 0 始まりデータ行インデックス
        let rId: String        // "rId1", "rId2", …
        let filename: String   // "image1.jpg", …
        let width:  Int        // px
        let height: Int        // px
        let rowHtPt: Double    // この行の高さ（pt）― センタリング計算に使用
    }

    // MARK: - XML strings

    private static func contentTypesXML(hasImages: Bool) -> String {
        let extras = hasImages
            ? "\n  <Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>" +
              "\n  <Override PartName=\"/xl/drawings/drawing1.xml\"" +
              " ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>"
            : ""
        return """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml"           ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml"  ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml"             ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/sharedStrings.xml"      ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\(extras)
</Types>
"""
    }

    private static let relsXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
"""

    private static let workbookXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="PixCurate" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"""

    private static let workbookRelsXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"    Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"       Target="styles.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>
"""

    // style index 0: デフォルト  1: データ行(罫線)  2: ヘッダー行(青・白太字・罫線)
    private static let stylesXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="14"/><name val="Calibri"/></font>
    <font><b/><sz val="14"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF2E75B6"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left   style="thin"><color rgb="FF000000"/></left>
      <right  style="thin"><color rgb="FF000000"/></right>
      <top    style="thin"><color rgb="FF000000"/></top>
      <bottom style="thin"><color rgb="FF000000"/></bottom>
      <diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
"""

    private static func sharedStringsXML(_ strs: [String]) -> String {
        let items = strs.map { "<si><t xml:space=\"preserve\">\(xe($0))</t></si>" }.joined()
        return """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(strs.count)" uniqueCount="\(strs.count)">\(items)</sst>
"""
    }

    private static func worksheetXML(dim: String, colCount: Int, columnWidths: [Double]?,
                                      rows: String, hasDrawing: Bool = false) -> String {
        var colDefs = ""
        if let widths = columnWidths, !widths.isEmpty {
            for (i, w) in widths.enumerated() {
                let col = i + 1
                colDefs += "<col min=\"\(col)\" max=\"\(col)\" width=\"\(w)\" customWidth=\"1\"/>"
            }
        } else {
            colDefs = "<col min=\"1\" max=\"1\" width=\"32\" customWidth=\"1\"/>"
            if colCount > 1 {
                colDefs += "<col min=\"2\" max=\"\(colCount)\" width=\"14\" customWidth=\"1\"/>"
            }
        }
        // 描画リレーション名前空間と要素（画像あり時のみ）
        let rNs    = hasDrawing
            ? "\n          xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
            : ""
        let drawEl = hasDrawing ? "\n  <drawing r:id=\"rId1\"/>" : ""
        return """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"\(rNs)>
  <dimension ref="\(dim)"/>
  <cols>\(colDefs)</cols>
  <sheetData>\(rows)</sheetData>
  <sheetView workbookViewId="0"><selection activeCell="A2" sqref="A2"/></sheetView>\(drawEl)
</worksheet>
"""
    }

    // MARK: - Drawing XML（画像の配置）

    /// 各行のセル A にサムネイルを配置する drawing1.xml
    private static func drawingXML(imageEntries: [ImageEntry]) -> String {
        // 単位換算
        let emuPerPx = 9525            // 1px = 9525 EMU（96 DPI）
        let emuPerPt = 12700           // 1pt = 12700 EMU
        // 列 A 幅 = 22 chars × 7px/char ≈ 154px（Calibri 11pt 概算）
        let colAWidEmu = 22 * 7 * emuPerPx

        let anchors = imageEntries.map { entry in
            // anchor 行番号は 0 始まり（0 = ヘッダー行、1 = 最初のデータ行）
            let fromRow = entry.rowIndex + 1
            let cx = entry.width  * emuPerPx
            let cy = entry.height * emuPerPx
            // 水平中央: (列幅EMU - 画像幅EMU) / 2
            let colOff = max(0, (colAWidEmu - cx) / 2)
            // 垂直中央: (行高さEMU - 画像高さEMU) / 2
            let rowHtEmu = Int(entry.rowHtPt * Double(emuPerPt))
            let rowOff   = max(0, (rowHtEmu - cy) / 2)
            // oneCellAnchor: from + ext(cx,cy) で実サイズ固定 → アスペクト比維持
            return "  <xdr:oneCellAnchor>" +
                   "<xdr:from><xdr:col>0</xdr:col><xdr:colOff>\(colOff)</xdr:colOff>" +
                   "<xdr:row>\(fromRow)</xdr:row><xdr:rowOff>\(rowOff)</xdr:rowOff></xdr:from>" +
                   "<xdr:ext cx=\"\(cx)\" cy=\"\(cy)\"/>" +
                   "<xdr:pic>" +
                   "<xdr:nvPicPr>" +
                   "<xdr:cNvPr id=\"\(entry.rowIndex + 2)\" name=\"Picture \(entry.rowIndex + 1)\"/>" +
                   "<xdr:cNvPicPr/>" +
                   "</xdr:nvPicPr>" +
                   "<xdr:blipFill>" +
                   "<a:blip r:embed=\"\(entry.rId)\"/>" +
                   "<a:stretch><a:fillRect/></a:stretch>" +
                   "</xdr:blipFill>" +
                   "<xdr:spPr>" +
                   "<a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>" +
                   "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>" +
                   "</xdr:spPr>" +
                   "</xdr:pic>" +
                   "<xdr:clientData/>" +
                   "</xdr:oneCellAnchor>"
        }.joined(separator: "\n")

        return """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"
          xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
\(anchors)
</xdr:wsDr>
"""
    }

    /// drawing1.xml.rels – rId → メディアファイルのマッピング
    private static func drawingRelsXML(imageEntries: [ImageEntry]) -> String {
        let rels = imageEntries.map { e in
            "  <Relationship Id=\"\(e.rId)\" " +
            "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" " +
            "Target=\"../media/\(e.filename)\"/>"
        }.joined(separator: "\n")
        return """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
\(rels)
</Relationships>
"""
    }

    /// sheet1.xml.rels – シート → drawing1.xml
    private static let sheetRelsForDrawingXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>
</Relationships>
"""

    // XML 文字エスケープ
    private static func xe(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Minimal ZIP Writer (STORE / no compression)

private struct ZIPEntry { let filename: String; let data: Data }

private enum ZIPWriter {

    static func archive(_ entries: [ZIPEntry]) -> Data {
        var local   = Data()
        var central = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            offsets.append(UInt32(local.count))
            let crc  = crc32(entry.data)
            let size = UInt32(entry.data.count)
            local.append(localHeader(name: entry.filename, size: size, crc: crc))
            local.append(entry.data)
            central.append(centralHeader(name: entry.filename, size: size, crc: crc, offset: offsets.last!))
        }

        local.append(central)
        local.append(eocd(count: UInt16(entries.count),
                          cdSize: UInt32(central.count),
                          cdOffset: UInt32(local.count - central.count)))
        return local
    }

    // MARK: CRC-32 (pure Swift)

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: Headers

    private static func localHeader(name: String, size: UInt32, crc: UInt32) -> Data {
        let n = Data(name.utf8)
        var d = Data()
        d += u32(0x04034b50); d += u16(20);   d += u16(0); d += u16(0)  // sig, ver, flag, method
        d += u16(0);          d += u16(0)                                  // mtime, mdate
        d += u32(crc);        d += u32(size);  d += u32(size)              // crc, comp, uncomp
        d += u16(UInt16(n.count)); d += u16(0)                             // namelen, extralen
        d += n
        return d
    }

    private static func centralHeader(name: String, size: UInt32, crc: UInt32, offset: UInt32) -> Data {
        let n = Data(name.utf8)
        var d = Data()
        d += u32(0x02014b50); d += u16(20);   d += u16(20); d += u16(0); d += u16(0) // sig,ver,vermin,flag,method
        d += u16(0);          d += u16(0)                                               // mtime, mdate
        d += u32(crc);        d += u32(size);  d += u32(size)                           // crc, comp, uncomp
        d += u16(UInt16(n.count)); d += u16(0); d += u16(0)                             // namelen, extralen, commentlen
        d += u16(0);          d += u16(0);     d += u32(0);   d += u32(offset)          // disk, iattr, eattr, offset
        d += n
        return d
    }

    private static func eocd(count: UInt16, cdSize: UInt32, cdOffset: UInt32) -> Data {
        var d = Data()
        d += u32(0x06054b50); d += u16(0); d += u16(0)            // sig, disk, startdisk
        d += u16(count);      d += u16(count)                      // entries on disk, total
        d += u32(cdSize);     d += u32(cdOffset); d += u16(0)      // cdSize, cdOffset, commentlen
        return d
    }

    // MARK: Little-endian helpers

    private static func u16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func u32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
                                                          UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]) }
}

// Data += Data
private func += (lhs: inout Data, rhs: Data) { lhs.append(rhs) }
