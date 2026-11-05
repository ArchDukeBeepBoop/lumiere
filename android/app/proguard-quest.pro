# The Quest's app only. Meta Spatial SDK reaches its own classes from native code
# and by name (features, components, systems), so all of it is kept as shipped:
# shrunk, two of its systems were merged into one class and the room refused to
# start ("already registered … Duplicate Systems are not allowed"). The rest is
# shrunk as on the phone and TV.
-keep class com.meta.spatial.** { *; }
-keep interface com.meta.spatial.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class * { native <methods>; }
-dontwarn com.meta.spatial.**
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
