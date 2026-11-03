package org.katsa.game;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.util.DisplayMetrics;

import org.libsdl.app.SDLActivity;
import org.libsdl.app.SDLSurface;

/**
 * The whole app is SDL's activity. SDL loads the libraries in order and calls SDL_main from the last
 * one (libmain.so, built from native/src/katsa_host.c). The Lua runtime then opens SDL2, OpenAL and
 * the katsa_* libraries again with dlopen; the loader returns the copies loaded here.
 *
 * Render height: phones have far more pixels than their GPUs can fill every frame (a 2460x1080
 * screen on a mid-range Mali). The surface is given a fixed, smaller size and Android scales it to
 * the screen in hardware. Set meta-data `katsa.renderHeight` in the manifest: a height in pixels
 * (default 720) or 0 for the native resolution.
 */
public class KatsaActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] {
            "SDL2", "openal", "katsa_native", "katsa_box2d", "katsa_net", "main"
        };
    }

    @Override
    protected SDLSurface createSDLSurface(Context context) {
        SDLSurface surface = new SDLSurface(context);
        int wanted = renderHeight();
        DisplayMetrics metrics = new DisplayMetrics();
        getWindowManager().getDefaultDisplay().getRealMetrics(metrics);
        int longSide = Math.max(metrics.widthPixels, metrics.heightPixels);
        int shortSide = Math.min(metrics.widthPixels, metrics.heightPixels);
        if (wanted > 0 && shortSide > wanted) {
            // The game runs in landscape: the short side is the height.
            int width = Math.round((float) longSide * wanted / shortSide);
            surface.getHolder().setFixedSize(width, wanted);
        }
        return surface;
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
