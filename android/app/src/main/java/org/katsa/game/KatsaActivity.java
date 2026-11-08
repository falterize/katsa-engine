package org.katsa.game;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.view.ViewGroup;
import android.widget.RelativeLayout;

import org.libsdl.app.SDLActivity;
import org.libsdl.app.SDLSurface;

/**
 * The whole app is SDL's activity. SDL loads the libraries in order and calls SDL_main from the last
 * one (libmain.so, built from native/src/host). The Lua runtime then opens SDL2, OpenAL and
 * the katsa_* libraries again with dlopen; the loader returns the copies loaded here.
 *
 * Render height: phones have far more pixels than their GPUs can fill every frame (a 2460x1080
 * screen on a mid-range Mali). The surface is given a fixed, smaller size and Android scales it to
 * the screen in hardware. Set meta-data `katsa.renderHeight` in the manifest: a height in pixels
 * (default 720) or 0 for the native resolution. Portrait and landscape both work.
 */
public class KatsaActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] {
            "SDL2", "openal", "katsa_native", "katsa_box2d", "katsa_net", "main"
        };
    }

    private SDLSurface katsaSurface;

    @Override
    protected SDLSurface createSDLSurface(Context context) {
        SDLSurface surface = new SDLSurface(context);
        // A SurfaceView with a fixed buffer size and wrap_content would be measured as big as the
        // buffer; match_parent lets Android stretch the buffer over the whole screen.
        surface.setLayoutParams(new RelativeLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        katsaSurface = surface;
        applyRenderSize();
        return surface;
    }

    /** The short side of the buffer is renderHeight pixels in either orientation. */
    private void applyRenderSize() {
        if (katsaSurface == null) {
            return;
        }
        int wanted = renderHeight();
        DisplayMetrics metrics = new DisplayMetrics();
        getWindowManager().getDefaultDisplay().getRealMetrics(metrics);
        int width = metrics.widthPixels;
        int height = metrics.heightPixels;
        int shortSide = Math.min(width, height);
        if (wanted > 0 && shortSide > wanted) {
            float scale = (float) wanted / shortSide;
            katsaSurface.getHolder().setFixedSize(Math.round(width * scale), Math.round(height * scale));
        } else {
            // Native resolution: let the surface follow the view again.
            katsaSurface.getHolder().setSizeFromLayout();
        }
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        applyRenderSize();
    }

    private int renderHeight() {
        try {
            ApplicationInfo info = getPackageManager()
                .getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA);
            Bundle data = info.metaData;
            if (data != null) {
                return data.getInt("katsa.renderHeight", 720);
            }
        } catch (PackageManager.NameNotFoundException ignored) {
        }
        return 720;
    }
}
