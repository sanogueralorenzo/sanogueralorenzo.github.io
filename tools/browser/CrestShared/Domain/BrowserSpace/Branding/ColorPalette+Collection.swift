import Foundation

/// A palette is its colors in order, so it reads, edits and grows as they do.
extension ColorPalette: RandomAccessCollection, MutableCollection, RangeReplaceableCollection,
    ExpressibleByArrayLiteral
{
    // MARK: - Variables

    var startIndex: Int { colors.startIndex }
    var endIndex: Int { colors.endIndex }

    subscript(position: Int) -> BrandColor {
        get { colors[position] }
        set { colors[position] = newValue }
    }

    // MARK: - Initializers

    init() {
        self.init(colors: [])
    }

    init(arrayLiteral colors: BrandColor...) {
        self.init(colors: colors)
    }

    // MARK: - Actions - Editing

    mutating func replaceSubrange<Colors: Collection>(_ subrange: Range<Int>, with newColors: Colors)
    where Colors.Element == BrandColor {
        colors.replaceSubrange(subrange, with: newColors)
    }
}
