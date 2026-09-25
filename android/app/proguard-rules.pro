# cf https://developer.android.com/topic/performance/app-optimization/add-keep-rules

# e.g. com.drew.metadata.exif.ExifSubIFDDirectory
-keep class com.drew.metadata.**{ *; }

-keep class org.beyka.tiffbitmapfactory.**{ *; }

-keep class org.mp4parser.**{ *; }

# referenced from: com.google.crypto.tink
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# Face recognition & detection: ML Kit, Firebase Components, TFLite
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }

-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

-keep class deckers.thibault.aves.channel.calls.FaceHandler { *; }

