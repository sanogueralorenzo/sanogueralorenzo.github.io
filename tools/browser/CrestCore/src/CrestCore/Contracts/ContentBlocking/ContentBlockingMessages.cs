namespace CrestCore.Contracts;

#region Models

/// A content rule list: the versioned identifier a rule-list store compiles it
/// under, and its WebKit content-rule JSON source.
public sealed record ContentRuleList(string Identifier, string Source);

#endregion
