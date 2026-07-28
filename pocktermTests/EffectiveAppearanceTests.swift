import Testing
@testable import pockterm

@Test func appearanceHostValuesWin() {
    let r = EffectiveHostSettings.resolveAppearance(
        hostTheme: "nord", hostFont: "Courier", hostSize: 18,
        chain: [(theme: "dracula", font: "Menlo-Regular", size: 20)])
    #expect(r.theme == "nord")
    #expect(r.font == "Courier")
    #expect(r.size == 18)
}

@Test func appearanceInheritsFromNearestGroup() {
    let r = EffectiveHostSettings.resolveAppearance(
        hostTheme: nil, hostFont: nil, hostSize: 0,
        chain: [(theme: nil, font: nil, size: nil),
                (theme: "dracula", font: "SFMono-Regular", size: 22)])
    #expect(r.theme == "dracula")
    #expect(r.font == "SFMono-Regular")
    #expect(r.size == 22)
}

@Test func appearanceFallsBackToDefaults() {
    let r = EffectiveHostSettings.resolveAppearance(
        hostTheme: nil, hostFont: nil, hostSize: 0, chain: [])
    #expect(r.theme == "default")
    #expect(r.font == "system")
    #expect(r.size == 12)
}

@Test func appearanceSizeSentinelZeroInherits() {
    let r = EffectiveHostSettings.resolveAppearance(
        hostTheme: nil, hostFont: nil, hostSize: 0,
        chain: [(theme: nil, font: nil, size: 16)])
    #expect(r.size == 16)
}
