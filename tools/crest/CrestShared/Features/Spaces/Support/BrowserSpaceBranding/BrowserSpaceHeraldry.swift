import SwiftUI

/// A term in Crest's heraldic vocabulary, whose name the core declares with
/// the term, so the catalog extracts it from the generated contracts.
protocol BrowserSpaceHeraldicTerm {
    var title: LocalizedStringResource { get }
}

extension SpaceIconStyle: BrowserSpaceHeraldicTerm {}
extension SpaceBannerPattern: BrowserSpaceHeraldicTerm {}
extension SpaceTextColorMode: BrowserSpaceHeraldicTerm {}
extension SpaceThemeMode: BrowserSpaceHeraldicTerm {}
extension CrestBackplate: BrowserSpaceHeraldicTerm {}
extension CrestChargeKind: BrowserSpaceHeraldicTerm {}
extension CrestChargeLayout: BrowserSpaceHeraldicTerm {}
extension CrestChargeWeight: BrowserSpaceHeraldicTerm {}
extension CrestDepth: BrowserSpaceHeraldicTerm {}
extension CrestFieldDivision: BrowserSpaceHeraldicTerm {}
extension CrestFinish: BrowserSpaceHeraldicTerm {}
extension CrestMonogramStyle: BrowserSpaceHeraldicTerm {}
extension CrestOrdinary: BrowserSpaceHeraldicTerm {}
extension CrestSymbol: BrowserSpaceHeraldicTerm {}
extension CrestTrim: BrowserSpaceHeraldicTerm {}
