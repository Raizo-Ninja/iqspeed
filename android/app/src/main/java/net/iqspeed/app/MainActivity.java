package net.iqspeed.app;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintManager;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

public class MainActivity extends Activity {
    static final String HOST = "iqspeed.net";
    static final String HOME = "https://" + HOST + "/";
    static final String OFFLINE = "file:///android_asset/offline.html";

    private WebView web;
    private SwipeRefreshLayout swipe;
    private volatile boolean busy = false;

    // Watches the page's Start button: while a test runs, block pull-to-refresh and keep the screen on.
    // Also routes window.print() to Android printing and "copy report" to the share sheet.
    private static final String GLUE =
        "(function(){if(window.__iqGlue)return;window.__iqGlue=1;" +
        "window.print=function(){AndroidBridge.print();};" +
        "var b=document.getElementById('startBtn');if(b){var f=function(){AndroidBridge.setBusy(!!b.disabled);};" +
        "new MutationObserver(f).observe(b,{attributes:true,attributeFilter:['disabled']});f();}})();";

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFF070B16);
        swipe = new SwipeRefreshLayout(this);
        swipe.setColorSchemeColors(0xFF3EE0FF, 0xFF7C6CFF);
        swipe.setProgressBackgroundColorSchemeColor(0xFF0D1425);
        web = new WebView(this);
        web.setBackgroundColor(0xFF070B16);
        swipe.addView(web, new ViewGroup.LayoutParams(-1, -1));
        root.addView(swipe, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);

        ViewCompat.setOnApplyWindowInsetsListener(root, (v, insets) -> {
            Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsetsCompat.CONSUMED;
        });

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setUserAgentString(s.getUserAgentString() + " IQSpeedApp/" + BuildConfig.VERSION_NAME);

        web.addJavascriptInterface(new Bridge(), "AndroidBridge");
        web.setWebViewClient(new Client());
        swipe.setOnRefreshListener(() -> { if (busy) { swipe.setRefreshing(false); return; } web.reload(); });
        swipe.setOnChildScrollUpCallback((parent, child) -> busy || web.getScrollY() > 0);

        if (savedInstanceState != null) web.restoreState(savedInstanceState);
        else web.loadUrl(startUrl(getIntent()));
    }

    private String startUrl(Intent i) {
        Uri u = i != null ? i.getData() : null;
        if (u != null && "https".equals(u.getScheme()) && HOST.equals(u.getHost())) return u.toString();
        return HOME;
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (intent.getData() != null && !busy) web.loadUrl(startUrl(intent));
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {
        if (web.canGoBack() && !OFFLINE.equals(web.getUrl())) web.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (web != null) { web.stopLoading(); web.destroy(); }
        super.onDestroy();
    }

    private boolean isOurs(Uri u) {
        return u != null && "https".equals(u.getScheme()) && HOST.equals(u.getHost());
    }

    private class Client extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
            Uri u = req.getUrl();
            if (isOurs(u)) return false;
            if ("file".equals(u.getScheme())) return true;
            try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (ActivityNotFoundException ignored) { }
            return true;
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            swipe.setRefreshing(false);
            if (isOurs(Uri.parse(url))) view.evaluateJavascript(GLUE, null);
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError err) {
            if (req.isForMainFrame()) {
                swipe.setRefreshing(false);
                view.getSettings().setAllowFileAccess(true);
                view.loadUrl(OFFLINE);
            }
        }
    }

    /** Only callable by pages from iqspeed.net or the bundled offline page. */
    class Bridge {
        private boolean allowed() {
            final String[] u = new String[1];
            final Object lock = new Object();
            synchronized (lock) {
                web.post(() -> { synchronized (lock) { u[0] = web.getUrl(); lock.notify(); } });
                try { lock.wait(500); } catch (InterruptedException ignored) { }
            }
            String url = u[0];
            return url != null && (url.startsWith(HOME) || url.equals(OFFLINE));
        }

        @JavascriptInterface
        public void setBusy(boolean b) {
            if (!allowed()) return;
            busy = b;
            runOnUiThread(() -> {
                if (b) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                swipe.setEnabled(!b);
            });
        }

        @JavascriptInterface
        public void share(String text) {
            if (!allowed() || text == null) return;
            runOnUiThread(() -> {
                Intent i = new Intent(Intent.ACTION_SEND);
                i.setType("text/plain");
                i.putExtra(Intent.EXTRA_TEXT, text.length() > 20000 ? text.substring(0, 20000) : text);
                startActivity(Intent.createChooser(i, null));
            });
        }

        @JavascriptInterface
        public void print() {
            if (!allowed()) return;
            runOnUiThread(() -> {
                PrintManager pm = (PrintManager) getSystemService(Context.PRINT_SERVICE);
                PrintDocumentAdapter ad = web.createPrintDocumentAdapter("iqspeed-report");
                pm.print("iqspeed-report", ad, new PrintAttributes.Builder().build());
            });
        }

        @JavascriptInterface
        public void retry() {
            runOnUiThread(() -> {
                web.getSettings().setAllowFileAccess(false);
                web.clearHistory();
                web.loadUrl(HOME);
            });
        }
    }
}
