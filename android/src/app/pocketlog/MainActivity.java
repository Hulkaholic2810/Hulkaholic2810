package app.pocketlog;

import android.app.Activity;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.Method;

/**
 * Pocket Lift Log for Android: a full-screen WebView around the same single-file web app.
 * The page is loaded under a fixed https origin so its localStorage (the whole log) persists between launches.
 */
public class MainActivity extends Activity {
    private static final String BASE = "https://pocketlog.app/";
    private static final int PAPER = 0xFFF9F8F6;
    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        setBars(PAPER, false);

        web = new WebView(this);
        web.setBackgroundColor(PAPER);
        web.setVerticalScrollBarEnabled(false);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setSupportZoom(false);

        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                if (url.startsWith(BASE)) return false;
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                } catch (Exception ignored) {
                }
                return true;
            }
        });
        web.addJavascriptInterface(new Bridge(), "PocketLogApp");
        web.loadDataWithBaseURL(BASE, readAsset("index.html"), "text/html", "utf-8", null);
        setContentView(web);
    }

    @Override
    protected void onPause() {
        // save immediately when leaving the app, then let the page idle
        js("window.__pocketSave && __pocketSave()");
        web.onPause();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
    }

    @Override
    public void onBackPressed() {
        // the page closes its menu first; on the log itself it calls exit()
        js("window.__pocketBack ? __pocketBack() : PocketLogApp.exit()");
    }

    private void js(String code) {
        if (web != null) web.loadUrl("javascript:void((function(){" + code + "})())");
    }

    private String readAsset(String name) {
        try {
            InputStream in = getAssets().open(name);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            in.close();
            return out.toString("UTF-8");
        } catch (Exception e) {
            return "<p>Could not open the log.</p>";
        }
    }

    /** Colour the status and navigation bars to match the paper (Android 5+), with dark icons on light paper. */
    private void setBars(int color, boolean night) {
        Window w = getWindow();
        try {
            Method status = Window.class.getMethod("setStatusBarColor", int.class);
            Method nav = Window.class.getMethod("setNavigationBarColor", int.class);
            w.addFlags(0x80000000); // FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS
            status.invoke(w, color);
            nav.invoke(w, color);
        } catch (Exception ignored) {
        }
        int flags = 0;
        if (!night && Build.VERSION.SDK_INT >= 23) flags |= 0x00002000; // SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        if (!night && Build.VERSION.SDK_INT >= 26) flags |= 0x00000010; // SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        w.getDecorView().setSystemUiVisibility(flags);
    }

    public class Bridge {
        @JavascriptInterface
        public void setBars(final String hex, final boolean night) {
            runOnUiThread(new Runnable() {
                public void run() {
                    try {
                        int c = Color.parseColor(hex.trim());
                        MainActivity.this.setBars(c, night);
                        web.setBackgroundColor(c);
                    } catch (Exception ignored) {
                    }
                }
            });
        }

        @JavascriptInterface
        public boolean isNight() {
            int mode = getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
            return mode == Configuration.UI_MODE_NIGHT_YES;
        }

        @JavascriptInterface
        public void exit() {
            runOnUiThread(new Runnable() {
                public void run() {
                    finish();
                }
            });
        }
    }
}
