# TensorFlow Lite GPU Delegate (may not be available in all configurations)
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
-dontwarn org.tensorflow.lite.gpu.GpuDelegate$Options
-dontwarn org.tensorflow.lite.gpu.**

# Keep TFLite classes if present
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.Interpreter { *; }
-keep class org.tensorflow.lite.Interpreter$Options { *; }
-keep class org.tensorflow.lite.Tensor { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Avoid obfuscation of critical TFLite classes
-keepnames class org.tensorflow.lite.**
-keepnames interface org.tensorflow.lite.**

# Keep Flutter components
-keepclasseswithmembernames class * {
    *** on*(***);
}
