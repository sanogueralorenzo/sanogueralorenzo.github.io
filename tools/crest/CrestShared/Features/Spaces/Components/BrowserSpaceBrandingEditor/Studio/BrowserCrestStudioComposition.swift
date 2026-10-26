import SwiftUI

struct BrowserCrestStudioComposition: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    private var preview: SpaceBranding? { context.compact ? context.value : nil }

    var body: some View {
        BrowserCrestStudioGroup(step: .shape, preview: preview, symbol: symbol) {
            gallery("Plate", \.backplate, CrestBackplate.all)
            if context.value.crest.backplate.hasTeeth {
                context.count("Teeth", \.sealTeeth, range: CrestMeasure.sealTeeth.countRange)
            }
            context.slider("Edge weight", \.edgeWidth, range: CrestMeasure.edgeWidth.range)
            BrowserCrestStudioColorRow(context: context, title: "Edge & outline", path: \.edgeColorIndex)
            context.slider("Plate size", \.plateScale, range: CrestMeasure.plateScale.range)
        }
        BrowserCrestStudioGroup(step: .field, preview: preview, symbol: symbol) {
            gallery("Division", \.fieldDivision, CrestFieldDivision.all)
            BrowserCrestStudioColorRow(context: context, title: "Field color", path: \.backplateColorIndex)
            if context.value.crest.fieldDivision != .plain {
                BrowserCrestStudioColorRow(context: context, title: "Second field", path: \.secondaryFieldColorIndex)
            }
            if context.value.crest.fieldDivision.isCounted {
                context.count("Repeats", \.divisionCount, range: CrestMeasure.divisionCount.countRange)
            }
            context.picker("Finish", \.finish, options: CrestFinish.all)
            if context.value.crest.finish.hasAngle {
                context.slider(
                    "Sheen angle", \.sheenAngle, range: CrestMeasure.sheenAngle.range, readout: .init { "\(Int($0))°" })
            }
        }
    }

    private func gallery<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<SpaceCrest, Option>, _ options: [Option]
    ) -> some View {
        BrowserCrestStudioGallery(context: context, title: title, path: path, options: options)
    }
}

struct BrowserCrestStudioOrnaments: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    private var preview: SpaceBranding? { context.compact ? context.value : nil }

    var body: some View {
        BrowserCrestStudioGroup(step: .band, preview: preview, symbol: symbol) {
            BrowserCrestStudioGallery(
                context: context, title: "Design", path: \.ordinary, options: CrestOrdinary.all)
            if context.value.crest.ordinary != .none {
                BrowserCrestStudioColorRow(context: context, title: "Band color", path: \.ordinaryColorIndex)
                context.slider("Width", \.ordinaryWidth, range: CrestMeasure.ordinaryWidth.range)
            }
        }
        BrowserCrestStudioGroup(step: .border, preview: preview, symbol: symbol) {
            BrowserCrestStudioGallery(
                context: context, title: "Design", path: \.trim, options: CrestTrim.all)
            if context.value.crest.trim != .none {
                BrowserCrestStudioColorRow(context: context, title: "Border color", path: \.trimColorIndex)
                context.slider("Weight", \.trimWeight, range: CrestMeasure.trimWeight.range)
            }
            if context.value.crest.trim.isCounted {
                context.count("Details", \.trimDetail, range: CrestMeasure.trimDetail.countRange)
            }
        }
        BrowserCrestStudioGroup(title: "Depth", systemImage: "square.3.layers.3d", preview: preview, symbol: symbol) {
            context.picker("Shadow", \.depth, options: CrestDepth.all)
            let outline = context.crest(\.showsOutline)
            CrestSettingRow("Outline", setting: outline.resettable("Outline")) {
                Toggle("Outline", isOn: outline.binding).labelsHidden()
            }
            if outline.wrappedValue {
                BrowserCrestStudioColorRow(context: context, title: "Edge & outline", path: \.edgeColorIndex)
            }
        }
    }
}

#if DEBUG
    #Preview("Interactive crest controls") {
        @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
        Form {
            BrowserCrestStudioComposition(
                context: BrowserCrestStudioContext(
                    branding: $branding, defaults: BrowserSpaceBrandingPreviewFixture.crestBranding, compact: false),
                symbol: "crown.fill")
        }.crestSettingsForm().frame(width: 480, height: 650)
    }
#endif
