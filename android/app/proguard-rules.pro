# Media3, OkHttp and Coil ship their own rules. Nothing here is reflected on
# except the widget and service, which the manifest keeps.
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# libass's burned-in subtitles (AssRenderType.CANVAS) build Media3's effects
# pipeline by reflection; stripped, the video renderer failed at once and the
# film played as sound alone.
-keep class androidx.media3.effect.** { *; }
