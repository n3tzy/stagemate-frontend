# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Kakao SDK
-keep class com.kakao.sdk.** { *; }
-dontwarn com.kakao.sdk.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# OkHttp / Retrofit (http 패키지 내부)
-dontwarn okhttp3.**
-dontwarn okio.**

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# image_cropper (uCrop)
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# in_app_purchase
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# 일반 직렬화 보호
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
