namespace CrestCore.Domain;

/// The order saved choices are listed in: by origin as a person reads it,
/// case-insensitively and with numbers compared by value, then by the
/// capability's stored name, then by detail.
public sealed class SitePermissionRecordOrder : IComparer<SitePermissionRecord> {
    #region Variables

    public static readonly SitePermissionRecordOrder Instance = new();

    #endregion

    #region Actions - Ordering

    public int Compare(SitePermissionRecord? x, SitePermissionRecord? y) {
        if (ReferenceEquals(x, y)) return 0;
        if (x is null) return -1;
        if (y is null) return 1;
        int origin = Natural(x.Origin.DisplayName, y.Origin.DisplayName);
        if (origin != 0) return origin;
        int permission = string.CompareOrdinal(x.Permission.Name, y.Permission.Name);
        return permission != 0 ? permission : string.CompareOrdinal(x.Detail ?? "", y.Detail ?? "");
    }

    private static int Natural(string left, string right) {
        int i = 0, j = 0;
        while (i < left.Length && j < right.Length) {
            if (char.IsAsciiDigit(left[i]) && char.IsAsciiDigit(right[j])) {
                int leftStart = i, rightStart = j;
                while (i < left.Length && char.IsAsciiDigit(left[i])) i++;
                while (j < right.Length && char.IsAsciiDigit(right[j])) j++;
                var leftDigits = left.AsSpan(leftStart, i - leftStart).TrimStart('0');
                var rightDigits = right.AsSpan(rightStart, j - rightStart).TrimStart('0');
                if (leftDigits.Length != rightDigits.Length) return leftDigits.Length.CompareTo(rightDigits.Length);
                int digits = leftDigits.SequenceCompareTo(rightDigits);
                if (digits != 0) return digits;
                continue;
            }
            int character = char.ToLowerInvariant(left[i]).CompareTo(char.ToLowerInvariant(right[j]));
            if (character != 0) return character;
            i++;
            j++;
        }
        return (left.Length - i).CompareTo(right.Length - j);
    }

    #endregion
}
