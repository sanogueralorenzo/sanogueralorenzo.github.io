# Valve bootstrap ZIPs permit only stored/deflate entries. Commons Compress's
# optional Zstandard reader is never used, so its JNI dependency is omitted.
-dontwarn com.github.luben.zstd.ZstdInputStream

# JavaSteam selects BC reflectively; BC discovers cipher mappings by class name.
-keep class org.bouncycastle.jce.provider.BouncyCastleProvider { *; }
-keep class org.bouncycastle.jcajce.provider.** { *; }
