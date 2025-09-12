# Keep all TensorFlow Lite core and GPU classes
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.gpu.**

# Optional: If you're using any delegates explicitly
-keep class org.tensorflow.lite.Delegate { *; }
