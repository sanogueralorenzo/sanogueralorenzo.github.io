# Valve bootstrap ZIPs permit only stored/deflate entries. Commons Compress's
# optional Zstandard reader is never used, so its JNI dependency is omitted.
-dontwarn com.github.luben.zstd.ZstdInputStream
