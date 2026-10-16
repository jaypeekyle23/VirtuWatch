# Release (R8) rules for the native AR try-on pipeline.
#
# Filament and MediaPipe call back into Java/Kotlin classes and fields from native (JNI) code, by name.
# R8 can't see those calls, so without these rules it removes or renames the classes in release builds
# and the app crashes as soon as the AR try-on screen creates its native view. Debug builds don't
# shrink, which is why it can work with `flutter run` and crash in a release APK.

# Filament (renderer, glTF loader, utils)
-keep class com.google.android.filament.** { *; }
-dontwarn com.google.android.filament.**

# MediaPipe tasks (hand landmarker) and the protobuf classes it uses
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.**

# Our own native view code (looked up by name from the platform-view registry / JNI)
-keep class com.urbanetime.virtuwatch.** { *; }
