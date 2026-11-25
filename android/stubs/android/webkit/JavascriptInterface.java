package android.webkit;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Compile-time stand-in for the platform annotation (added in API 17), which the API 16 stub jar
 * used for compiling lacks. It is only on the compile classpath and is never packaged: at runtime
 * the device's own android.webkit.JavascriptInterface is used.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface JavascriptInterface {
}
