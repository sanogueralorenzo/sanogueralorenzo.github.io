using System.Text;

namespace CrestCore.Domain;

/// Writes comma-separated text as RFC 4180 spells it: every field in double
/// quotes, its own quotes doubled, and every row, the last included, ended by
/// a carriage return and a line feed.
public static class CsvWriter {
    #region Actions - Writing

    /// `rows` as CSV text.
    public static string Write(IEnumerable<IReadOnlyList<string>> rows) {
        ArgumentNullException.ThrowIfNull(rows);
        var text = new StringBuilder();
        foreach (var row in rows) {
            for (int index = 0; index < row.Count; index++) {
                if (index > 0) text.Append(',');
                text.Append('"').Append(row[index].Replace("\"", "\"\"", StringComparison.Ordinal)).Append('"');
            }
            text.Append("\r\n");
        }
        return text.ToString();
    }

    #endregion
}
