# gomobile: Go дёргает Java-классы по имени через JNI
-keep class go.** { *; }
-keep class libXray.** { *; }
# hev-socks5-tunnel регистрирует natives на hev.htproxy.TProxyService
-keep class hev.htproxy.** { *; }
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**
-dontwarn javax.naming.**
