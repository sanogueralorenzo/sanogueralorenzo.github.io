using System.Globalization;

namespace CrestCore.Domain;

/// Stable fractional positions preserve unmoved records during sync staging.
public static class SyncOrderTokens {
    #region Actions - Sync

    public static IReadOnlyList<string> Allocate(IReadOnlyList<string?> existing) {
        if (existing.Count > 250_000) throw new BrowserRuleException(BrowserRule.SyncRecordLimit);
        if (existing.Count == 0) return [];
        var candidates = existing.Select((token, index) => (token, index))
            .Where(v => v.token is { Length: 16 } token && ulong.TryParse(token, NumberStyles.HexNumber,
                CultureInfo.InvariantCulture, out var value) && Encode(value) == token)
            .Select(v => (Index: v.index, Value: ulong.Parse(v.token!, NumberStyles.HexNumber, CultureInfo.InvariantCulture))).ToArray();
        if (candidates.Length == 0) return Compact(existing.Count);
        var tails = new List<ulong>(); var tailIndices = new List<int>();
        var predecessors = Enumerable.Repeat(-1, candidates.Length).ToArray();
        for (int i = 0; i < candidates.Length; i++) {
            ulong value = candidates[i].Value;
            int low = 0, high = tails.Count;
            while (low < high) {
                int middle = low + (high - low) / 2;
                if (tails[middle] < value) low = middle + 1; else high = middle;
            }
            if (low > 0) predecessors[i] = tailIndices[low - 1];
            if (low == tails.Count) { tails.Add(value); tailIndices.Add(i); } else { tails[low] = value; tailIndices[low] = i; }
        }
        var anchors = new SortedDictionary<int, ulong>();
        for (int i = tailIndices[^1]; i >= 0; i = predecessors[i]) anchors.Add(candidates[i].Index, candidates[i].Value);
        var result = new string[existing.Count]; int previousIndex = -1; ulong? lower = null;
        foreach (var (index, value) in anchors) {
            if (!Distribute(result, previousIndex + 1, index - previousIndex - 1, lower, value)) return Compact(existing.Count);
            result[index] = Encode(value); previousIndex = index; lower = value;
        }
        return Distribute(result, previousIndex + 1, existing.Count - previousIndex - 1, lower, null)
            ? result : Compact(existing.Count);
    }

    private static string Encode(ulong value) => value.ToString("x16", CultureInfo.InvariantCulture);

    private static string[] Compact(int count) {
        ulong step = ulong.MaxValue / ((ulong)count + 1);
        return Enumerable.Range(1, count).Select(i => Encode(step * (ulong)i)).ToArray();
    }

    private static bool Distribute(string[] result, int start, int count, ulong? lower, ulong? upper) {
        if (count == 0) return true;
        if (lower is { } low && upper is { } high && low >= high) return false;
        ulong distance = (upper ?? ulong.MaxValue) - (lower ?? 0);
        ulong step = distance / ((ulong)count + 1);
        if (step == 0) return false;
        for (int i = 0; i < count; i++) result[start + i] = Encode((lower ?? 0) + step * ((ulong)i + 1));
        return true;
    }

    #endregion
}
