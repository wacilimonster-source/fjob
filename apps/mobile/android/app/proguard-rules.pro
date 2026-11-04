# WorkManager opens its Room database implementation reflectively through
# androidx.startup. R8 full mode must keep the generated constructor, otherwise
# release builds crash at startup with:
#   NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>(...);
}
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.startup.** { *; }
