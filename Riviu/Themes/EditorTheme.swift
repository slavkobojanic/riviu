import AppKit

/// Editor color themes. Each family has a light and a dark variant; the variant follows the window appearance.

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum EditorThemeFamily: String, CaseIterable, Identifiable {
    case one = "One", github = "GitHub", xcode = "Xcode", solarized = "Solarized", catppuccin = "Catppuccin"
    var id: String { rawValue }

    /// The names of the light and dark variants, for the theme picker.
    var variantNames: String {
        switch self {
        case .one: "One Light / One Dark"
        case .github: "GitHub Light / GitHub Dark"
        case .xcode: "Xcode Light / Xcode Dark"
        case .solarized: "Solarized Light / Solarized Dark"
        case .catppuccin: "Catppuccin Latte / Mocha"
        }
    }

    func theme(dark: Bool) -> EditorTheme {
        switch (self, dark) {
        case (.one, true):
            EditorTheme(name: "One Dark", isDark: true, background: 0x282C34, foreground: 0xABB2BF, lineNumber: 0x636D83, selection: 0x3E4451,
                       palette: .init(keyword: 0xC678DD, string: 0x98C379, comment: 0x7F848E, number: 0xD19A66, type: 0xE5C07B, function: 0x61AFEF,
                                constant: 0xD19A66, property: 0xE06C75, builtin: 0xE5C07B, parameter: 0xABB2BF, op: 0x56B6C2,
                                punctuation: 0xABB2BF, attribute: 0xD19A66, heading: 0xE06C75, escape: 0x56B6C2, link: 0x61AFEF))
        case (.one, false):
            EditorTheme(name: "One Light", isDark: false, background: 0xFAFAFA, foreground: 0x383A42, lineNumber: 0x9D9D9F, selection: 0xE5E5E6,
                       palette: .init(keyword: 0xA626A4, string: 0x50A14F, comment: 0xA0A1A7, number: 0x986801, type: 0xC18401, function: 0x4078F2,
                                constant: 0x986801, property: 0xE45649, builtin: 0xC18401, parameter: 0x383A42, op: 0x0184BC,
                                punctuation: 0x383A42, attribute: 0x986801, heading: 0xE45649, escape: 0x0184BC, link: 0x4078F2))
        case (.github, true):
            EditorTheme(name: "GitHub Dark", isDark: true, background: 0x0D1117, foreground: 0xE6EDF3, lineNumber: 0x6E7681, selection: 0x264F78,
                       palette: .init(keyword: 0xFF7B72, string: 0xA5D6FF, comment: 0x8B949E, number: 0x79C0FF, type: 0xFFA657, function: 0xD2A8FF,
                                constant: 0x79C0FF, property: 0x79C0FF, builtin: 0xFFA657, parameter: 0xE6EDF3, op: 0xFF7B72,
                                punctuation: 0xE6EDF3, attribute: 0x79C0FF, heading: 0x79C0FF, escape: 0x79C0FF, link: 0xA5D6FF))
        case (.github, false):
            EditorTheme(name: "GitHub Light", isDark: false, background: 0xFFFFFF, foreground: 0x1F2328, lineNumber: 0x8C959F, selection: 0xB6E3FF,
                       palette: .init(keyword: 0xCF222E, string: 0x0A3069, comment: 0x6E7781, number: 0x0550AE, type: 0x953800, function: 0x8250DF,
                                constant: 0x0550AE, property: 0x0550AE, builtin: 0x953800, parameter: 0x1F2328, op: 0xCF222E,
                                punctuation: 0x1F2328, attribute: 0x0550AE, heading: 0x0550AE, escape: 0x0550AE, link: 0x0A3069))
        case (.xcode, true):
            EditorTheme(name: "Xcode Dark", isDark: true, background: 0x1F1F24, foreground: 0xDFDFE0, lineNumber: 0x747478, selection: 0x515B70,
                       palette: .init(keyword: 0xFC5FA3, string: 0xFC6A5D, comment: 0x7F8C98, number: 0xD0BF69, type: 0x5DD8FF, function: 0x67B7A4,
                                constant: 0xD0BF69, property: 0x4EB0CC, builtin: 0xFC5FA3, parameter: 0xDFDFE0, op: 0xDFDFE0,
                                punctuation: 0xDFDFE0, attribute: 0xFD8F3F, heading: 0x5DD8FF, escape: 0xFC6A5D, link: 0x5482FF))
        case (.xcode, false):
            EditorTheme(name: "Xcode Light", isDark: false, background: 0xFFFFFF, foreground: 0x262626, lineNumber: 0xA6A6A6, selection: 0xB4D8FD,
                       palette: .init(keyword: 0x9B2393, string: 0xC41A16, comment: 0x5D6C79, number: 0x1C00CF, type: 0x0B4F79, function: 0x326D74,
                                constant: 0x1C00CF, property: 0x0F68A0, builtin: 0x9B2393, parameter: 0x262626, op: 0x262626,
                                punctuation: 0x262626, attribute: 0x815F03, heading: 0x0B4F79, escape: 0xC41A16, link: 0x0E0EFF))
        case (.solarized, true):
            EditorTheme(name: "Solarized Dark", isDark: true, background: 0x002B36, foreground: 0x839496, lineNumber: 0x586E75, selection: 0x073642,
                       palette: .init(keyword: 0x859900, string: 0x2AA198, comment: 0x586E75, number: 0xD33682, type: 0xB58900, function: 0x268BD2,
                                constant: 0xCB4B16, property: 0x268BD2, builtin: 0xCB4B16, parameter: 0x839496, op: 0x859900,
                                punctuation: 0x839496, attribute: 0x6C71C4, heading: 0xCB4B16, escape: 0xDC322F, link: 0x6C71C4))
        case (.solarized, false):
            EditorTheme(name: "Solarized Light", isDark: false, background: 0xFDF6E3, foreground: 0x657B83, lineNumber: 0x93A1A1, selection: 0xEEE8D5,
                       palette: .init(keyword: 0x859900, string: 0x2AA198, comment: 0x93A1A1, number: 0xD33682, type: 0xB58900, function: 0x268BD2,
                                constant: 0xCB4B16, property: 0x268BD2, builtin: 0xCB4B16, parameter: 0x657B83, op: 0x859900,
                                punctuation: 0x657B83, attribute: 0x6C71C4, heading: 0xCB4B16, escape: 0xDC322F, link: 0x6C71C4))
        case (.catppuccin, true):
            EditorTheme(name: "Catppuccin Mocha", isDark: true, background: 0x1E1E2E, foreground: 0xCDD6F4, lineNumber: 0x6C7086, selection: 0x45475A,
                       palette: .init(keyword: 0xCBA6F7, string: 0xA6E3A1, comment: 0x9399B2, number: 0xFAB387, type: 0xF9E2AF, function: 0x89B4FA,
                                constant: 0xFAB387, property: 0xB4BEFE, builtin: 0xF38BA8, parameter: 0xEBA0AC, op: 0x89DCEB,
                                punctuation: 0x9399B2, attribute: 0xF9E2AF, heading: 0xF38BA8, escape: 0xF5C2E7, link: 0x89B4FA))
        case (.catppuccin, false):
            EditorTheme(name: "Catppuccin Latte", isDark: false, background: 0xEFF1F5, foreground: 0x4C4F69, lineNumber: 0x8C8FA1, selection: 0xCCD0DA,
                       palette: .init(keyword: 0x8839EF, string: 0x40A02B, comment: 0x7C7F93, number: 0xFE640B, type: 0xDF8E1D, function: 0x1E66F5,
                                constant: 0xFE640B, property: 0x7287FD, builtin: 0xD20F39, parameter: 0xE64553, op: 0x04A5E5,
                                punctuation: 0x7C7F93, attribute: 0xDF8E1D, heading: 0xD20F39, escape: 0xEA76CB, link: 0x1E66F5))
        }
    }
}

struct EditorTheme {
    struct Palette {
        var keyword, string, comment, number, type, function, constant, property, builtin, parameter, op, punctuation,
            attribute, heading, escape, link: UInt32
    }

    let name: String
    let isDark: Bool
    let background: NSColor
    let foreground: NSColor
    let lineNumber: NSColor
    let selection: NSColor
    let accent: NSColor
    private let syntax: [String: NSColor]

    init(name: String, isDark: Bool, background: UInt32, foreground: UInt32, lineNumber: UInt32, selection: UInt32, palette p: Palette) {
        self.name = name
        self.isDark = isDark
        self.background = NSColor(hex: background)
        self.foreground = NSColor(hex: foreground)
        self.lineNumber = NSColor(hex: lineNumber)
        self.selection = NSColor(hex: selection, alpha: isDark ? 0.9 : 1)
        accent = NSColor(hex: p.function)
        let map: [String: UInt32] = [
            "keyword": p.keyword, "punctuation.special": p.keyword,
            "string": p.string, "text.literal": p.string, "string.special.key": p.property,
            "string.escape": p.escape, "escape": p.escape, "string.regexp": p.escape, "character.special": p.escape,
            "comment": p.comment,
            "number": p.number, "boolean": p.constant, "constant": p.constant,
            "type": p.type, "constructor": p.type,
            "function": p.function,
            "property": p.property, "variable.member": p.property,
            "variable.builtin": p.builtin, "variable.parameter": p.parameter,
            "operator": p.op, "punctuation": p.punctuation,
            "attribute": p.attribute, "label": p.attribute,
            "text.title": p.heading, "text.uri": p.link, "text.reference": p.link,
            "tag": p.keyword, "tag.attribute": p.attribute,
            // Older capture names that some grammars (Kotlin, Elixir, Scala) still use.
            "conditional": p.keyword, "repeat": p.keyword, "include": p.keyword, "exception": p.keyword,
            "storageclass": p.keyword, "preproc": p.keyword,
            "method": p.function, "parameter": p.parameter, "field": p.property,
            "namespace": p.type, "module": p.type,
            "float": p.number, "character": p.string, "string.regex": p.escape, "string.special.regex": p.escape,
            "delimiter": p.punctuation,
        ]
        syntax = map.mapValues { NSColor(hex: $0) }
    }

    /// The color for a tree-sitter capture such as "function.method.call".
    /// Tries the full name, then "function.method", then "function".
    func color(for capture: String) -> NSColor? {
        var key = Substring(capture)
        while true {
            if let c = syntax[String(key)] { return c }
            guard let dot = key.lastIndex(of: ".") else { return nil }
            key = key[..<dot]
        }
    }
}
