# shared_preferences_android memanggil method Kotlin suspend lewat JNI dengan signature
# ...Lkotlin/coroutines/Continuation;. Jika R8 mengganti nama Continuation, build release
# crash (NoSuchMethodError: SharedPreferencesApiRegistrar.getAll) dan login/registrasi
# gagal tanpa pesan.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
