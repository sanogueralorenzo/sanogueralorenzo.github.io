namespace CrestCore.Contracts;

/// Whether Crest takes the address.
public sealed record ExternalAddressVerdict(bool Accepted);

/// Who owns the navigation.
public sealed record SchemeHandled(ExternalSchemeDisposition Disposition);
