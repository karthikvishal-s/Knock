import Foundation

/// RFC 4180 CSV: quoted fields, doubled quotes, commas/newlines inside quotes, CRLF or LF.
/// Also strips a UTF-8 BOM and auto-detects `,` / `;` / tab delimiters.
public enum CSVCodec {
    public static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        var input = Substring(text)
        if input.first == "\u{FEFF}" { input = input.dropFirst() }
        let separator = delimiter ?? detectDelimiter(String(input.prefix(4_096)))

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = input.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" && field.isEmpty {
                inQuotes = true
            } else if char == separator {
                endField()
            } else if char == "\n" || char == "\r\n" {
                endRow()
            } else if char == "\r" {
                continue
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    public static func encode(_ rows: [[String]], delimiter: Character = ",") -> String {
        rows.map { row in
            row.map { field in
                let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r")
                return needsQuotes ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }
            .joined(separator: String(delimiter))
        }
        .joined(separator: "\r\n") + "\r\n"
    }

    static func detectDelimiter(_ sample: String) -> Character {
        let firstLine = sample.split(whereSeparator: \.isNewline).first.map(String.init) ?? sample
        let candidates: [Character] = [",", ";", "\t"]
        return candidates.max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count } ?? ","
    }
}
