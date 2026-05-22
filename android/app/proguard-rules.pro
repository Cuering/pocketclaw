# ── PocketClaw release ProGuard / R8 rules ──────────────────────────────
#
# Keep rules required by flutter_gemma's transitive MediaPipe dependency.
# MediaPipe references proto-generated classes via reflection (JNI callbacks
# from native code into Java/Kotlin), so R8's default stripping breaks them
# at runtime.
#
# Generated 2026-05-21 in response to R8 errors:
#   Missing class com.google.mediapipe.proto.CalculatorProfileProto$...
#   Missing class com.google.mediapipe.proto.GraphTemplateProto$...

# Keep all MediaPipe proto classes — they're referenced from JNI.
-keep class com.google.mediapipe.proto.** { *; }
-dontwarn com.google.mediapipe.proto.**

# Keep the rest of the MediaPipe Java surface (framework + tasks) since
# native code calls into it reflectively. Cheaper than chasing each missing
# class one at a time.
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Keep protobuf generated code — MediaPipe builds on protobuf-lite.
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Keep flutter_gemma's own native bridges (FFI entry points). Belt + suspenders.
-keep class com.google.ai.edge.** { *; }
-dontwarn com.google.ai.edge.**

# Keep AutoValue / @Generated annotations referenced by MediaPipe.
-keep class * extends com.google.auto.value.** { *; }
-dontwarn com.google.auto.value.**

# Standard Flutter keep rules (in case flutter_tools didn't inject them).
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
