# Meta Spatial SDK reaches its own classes from native code and by name
# (features, components, systems), so all of it is kept as shipped. The rest
# — Compose, Media3, OkHttp, Coil and Lumiere's own code — is shrunk as on the phone.
-keep class com.meta.spatial.** { *; }
-keep interface com.meta.spatial.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class * { native <methods>; }
-dontwarn com.meta.spatial.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
