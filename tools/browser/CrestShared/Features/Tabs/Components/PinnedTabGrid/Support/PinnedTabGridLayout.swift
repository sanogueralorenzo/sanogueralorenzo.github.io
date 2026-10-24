import CoreGraphics

enum PinnedTabGridLayout {
    static let maximumColumns = 4

    static func columnCount(for itemCount: Int, maximumColumns: Int = maximumColumns) -> Int {
        let count = max(1, itemCount)
        let capacity = max(1, maximumColumns)
        let rows = (count + capacity - 1) / capacity
        return (count + rows - 1) / rows
    }
}
