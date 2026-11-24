# قواعد حماية Flutter الأساسية
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# حماية مكتبة قارئ الباركود (mobile_scanner) و CameraX و ML Kit
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class androidx.camera.** { *; }
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.camera2.** { *; }
-keep class androidx.camera.lifecycle.** { *; }
-keep class androidx.camera.view.** { *; }

-keepclassmembers class * extends androidx.camera.core.impl.ExtendableUseCaseConfigFactory {
    public <init>(...);
}

# حماية قاعدة البيانات المحلية والطباعة والمشاركات
-keep class com.tekartik.sqflite.** { *; }
-keep class net.nfet.flutter.printing.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }

# منع توقف البناء بسبب التحذيرات الثانوية في R8
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn androidx.camera.**
-dontwarn com.google.android.play.core.**
-dontwarn org.slf4j.**
-dontwarn javax.annotation.**
