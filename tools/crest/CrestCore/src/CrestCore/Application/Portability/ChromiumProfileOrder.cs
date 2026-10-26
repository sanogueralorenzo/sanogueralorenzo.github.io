namespace CrestCore.Application;

/// The order Chrome lists its profiles in: `Default` first, then the others
/// as Finder sorts names, counting runs of digits as numbers, so `Profile 2`
/// comes before `Profile 10`.
internal sealed class ChromiumProfileOrder : IComparer<string> {
    #region Static Variables

    public static ChromiumProfileOrder Instance { get; } = new();

    private const string DefaultProfile = "Default";

    #endregion

    #region Actions - Comparing

    public int Compare(string? first, string? second) {
        if (first == second) return 0;
        if (first is null) return -1;
        if (second is null) return 1;
        if (first == DefaultProfile) return -1;
        if (second == DefaultProfile) return 1;
        int left = 0, right = 0;
        while (left < first.Length && right < second.Length) {
            if (char.IsAsciiDigit(first[left]) && char.IsAsciiDigit(second[right])) {
                int leftEnd = Run(first, left), rightEnd = Run(second, right);
                var leftDigits = first.AsSpan(left, leftEnd - left).TrimStart('0');
                var rightDigits = second.AsSpan(right, rightEnd - right).TrimStart('0');
                int byLength = leftDigits.Length.CompareTo(rightDigits.Length);
                if (byLength != 0) return byLength;
                int byDigits = leftDigits.SequenceCompareTo(rightDigits);
                if (byDigits != 0) return byDigits;
                left = leftEnd;
                right = rightEnd;
                continue;
            }
            int byCharacter = char.ToUpperInvariant(first[left]).CompareTo(char.ToUpperInvariant(second[right]));
            if (byCharacter != 0) return byCharacter;
            left++;
            right++;
        }
        int byRemainder = (first.Length - left).CompareTo(second.Length - right);
        return byRemainder != 0 ? byRemainder : string.CompareOrdinal(first, second);
    }

    private static int Run(string text, int start) {
        int end = start;
        while (end < text.Length && char.IsAsciiDigit(text[end])) end++;
        return end;
    }

    #endregion
}
