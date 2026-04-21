# Keep Flutter and its native interfaces
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep MainActivity specifically to prevent ClassNotFoundException
-keep class com.zyiarah.app.MainActivity { *; }

# Keep Firebase and GMS
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
