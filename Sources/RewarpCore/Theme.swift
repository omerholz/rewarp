import CGhosttyVT

public struct RGB: Equatable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xff), UInt8((hex >> 8) & 0xff), UInt8(hex & 0xff))
    }

    var ghostty: GhosttyColorRgb { GhosttyColorRgb(r: r, g: g, b: b) }

    /// Mixes toward `other`. An amount of 0 returns self, 1 returns other.
    public func mixed(with other: RGB, _ amount: Double) -> RGB {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) * (1 - amount) + Double(b) * amount).rounded())
        }
        return RGB(mix(r, other.r), mix(g, other.g), mix(b, other.b))
    }
}

public struct Theme: Sendable {
    public var name: String
    public var isDark: Bool
    public var background: RGB
    public var foreground: RGB
    public var cursor: RGB
    public var accent: RGB
    public var selection: RGB
    /// The 16 ANSI colours: black through white, then the bright variants.
    public var ansi: [RGB]

    public init(name: String, isDark: Bool, background: RGB, foreground: RGB, cursor: RGB,
                accent: RGB, selection: RGB, ansi: [RGB]) {
        precondition(ansi.count == 16)
        self.name = name
        self.isDark = isDark
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.accent = accent
        self.selection = selection
        self.ansi = ansi
    }

    public static let dusk = Theme(
        name: "Dusk",
        isDark: true,
        background: RGB(hex: 0x14161B),
        foreground: RGB(hex: 0xE3E6EC),
        cursor: RGB(hex: 0x5FB3F7),
        accent: RGB(hex: 0x5FB3F7),
        selection: RGB(hex: 0x2F4A68),
        ansi: [
            RGB(hex: 0x23262E), RGB(hex: 0xF0717A), RGB(hex: 0x7FD08A), RGB(hex: 0xE8C468),
            RGB(hex: 0x6DB1F5), RGB(hex: 0xC792EA), RGB(hex: 0x5FD3D0), RGB(hex: 0xC8CDD6),
            RGB(hex: 0x5C6370), RGB(hex: 0xFF8E96), RGB(hex: 0x9CE6A6), RGB(hex: 0xF5D98B),
            RGB(hex: 0x93C8FA), RGB(hex: 0xDAB1F4), RGB(hex: 0x86E5E2), RGB(hex: 0xF4F6FA),
        ])
}
