using System.Globalization;

namespace CrestCore.Domain;

/// Arithmetic a person typed into the palette and its answer: numbers with
/// `+ − × ÷ ^ %`, parentheses and a leading minus, with at least one operator,
/// so a bare number or any word is never a calculation.
public sealed class Calculation {
    #region Static Variables

    /// The longest text the palette reads as a calculation.
    private const int MaximumLength = 128;

    /// The deepest parentheses the palette follows.
    private const int MaximumDepth = 32;

    #endregion

    #region Variables

    /// The expression as typed, trimmed.
    public string Expression { get; }

    /// The answer.
    public double Value { get; private init; }

    /// The answer as the palette shows and copies it: up to twelve
    /// significant digits, without trailing zeros.
    public string Answer => Value.ToString("G12", CultureInfo.InvariantCulture);

    private readonly string text;
    private int position;
    private int depth;
    private bool operated;

    #endregion

    #region Constructors

    private Calculation(string expression) {
        Expression = expression;
        text = expression;
    }

    #endregion

    #region Actions - Reading

    /// The calculation `typed` spells, or null when it is not arithmetic, has
    /// no operator, or has no finite answer.
    public static Calculation? Of(string typed) {
        ArgumentNullException.ThrowIfNull(typed);
        string trimmed = typed.Trim();
        if (trimmed.Length is 0 or > MaximumLength || !trimmed.Any(char.IsAsciiDigit)) return null;
        var calculation = new Calculation(trimmed);
        try {
            double value = calculation.Sum();
            calculation.SkipSpace();
            if (calculation.position != trimmed.Length || !calculation.operated || !double.IsFinite(value)) return null;
            return new Calculation(trimmed) { Value = value == 0 ? 0 : value };
        } catch (FormatException) {
            return null;
        }
    }

    private double Sum() {
        double value = Product();
        while (true) {
            SkipSpace();
            if (Take('+')) value += Product();
            else if (Take('-') || Take('−')) value -= Product();
            else return value;
            operated = true;
        }
    }

    private double Product() {
        double value = Power();
        while (true) {
            SkipSpace();
            if (Take('*') || Take('×') || Take('x')) value *= Power();
            else if (Take('/') || Take('÷')) value /= Power();
            else if (Take('%')) value %= Power();
            else return value;
            operated = true;
        }
    }

    private double Power() {
        double value = Unary();
        SkipSpace();
        if (!Take('^')) return value;
        operated = true;
        return Math.Pow(value, Power());
    }

    private double Unary() {
        SkipSpace();
        if (Take('-') || Take('−')) {
            operated = true;
            return -Unary();
        }
        if (Take('+')) return Unary();
        if (Take('(')) {
            if (++depth > MaximumDepth) throw new FormatException();
            double value = Sum();
            SkipSpace();
            if (!Take(')')) throw new FormatException();
            depth--;
            return value;
        }
        return Number();
    }

    private double Number() {
        SkipSpace();
        int start = position;
        while (position < text.Length && (char.IsAsciiDigit(text[position]) || text[position] == '.')) position++;
        if (position == start || !double.TryParse(text.AsSpan(start, position - start), NumberStyles.AllowDecimalPoint,
            CultureInfo.InvariantCulture, out double value)) throw new FormatException();
        return value;
    }

    private bool Take(char expected) {
        if (position >= text.Length || text[position] != expected) return false;
        position++;
        return true;
    }

    private void SkipSpace() {
        while (position < text.Length && char.IsWhiteSpace(text[position])) position++;
    }

    #endregion
}
