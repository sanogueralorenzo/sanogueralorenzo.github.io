using CrestCore.Contracts;

namespace CrestCore.Application;

/// A file an import reads whole, which the platform lets the core open for
/// the length of the read.
internal static class ImportFile {
    #region Actions - Reading

    /// The contents of the file at `path`. Throws `Rejected` with `tooLarge`
    /// for one larger than `maximum` bytes, `notAFile` for a path that names no
    /// file, and `FileUnreadable` for one that cannot be read.
    public static byte[] Read(string path, long maximum, Rejection tooLarge, Rejection notAFile) {
        ArgumentNullException.ThrowIfNull(path);
        try {
            var file = new FileInfo(path);
            if (!file.Exists) throw new Rejected(notAFile);
            if (file.Length > maximum) throw new Rejected(tooLarge);
            return File.ReadAllBytes(path);
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException) {
            throw new Rejected(new FileUnreadable());
        }
    }

    #endregion
}
