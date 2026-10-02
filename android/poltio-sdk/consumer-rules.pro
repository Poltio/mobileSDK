# Rules applied to host apps that minify with R8/ProGuard.

# The widget page calls into PoltioWebViewActivity's JS bridge by method name
# (window.PoltioNativeBridge.postMessage) — keep @JavascriptInterface methods so R8 doesn't
# rename or strip them, even in apps that don't use the default Android proguard file.
-keepclassmembers class com.poltio.sdk.** {
    @android.webkit.JavascriptInterface <methods>;
}
