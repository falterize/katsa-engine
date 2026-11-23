package org.katsa.game;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;
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

    /**
     * SDL divides touch positions by the buffer size, but Android reports them in view pixels. With
     * a fixed buffer smaller than the view that pushes every touch outward (the right side of the
     * screen falls outside 0..1 and the rest is offset), so touches are rescaled to buffer pixels.
     */
    private static final class KatsaSurface extends SDLSurface {
        KatsaSurface(Context context) {
            super(context);
        }

        @Override
        public boolean onTouch(View view, MotionEvent event) {
            Rect frame = getHolder().getSurfaceFrame();
            int viewWidth = getWidth();
            int viewHeight = getHeight();
            if (viewWidth <= 0 || viewHeight <= 0 || frame.width() <= 0) {
                return super.onTouch(view, event);
            }
            MotionEvent scaled = MotionEvent.obtain(event);
            Matrix matrix = new Matrix();
            matrix.setScale((float) frame.width() / viewWidth, (float) frame.height() / viewHeight);
            scaled.transform(matrix);
            boolean handled = super.onTouch(view, scaled);
            scaled.recycle();
            return handled;
        }
    }

    @Override
    protected SDLSurface createSDLSurface(Context context) {
        final KatsaSurface surface = new KatsaSurface(context);
        // A SurfaceView with a fixed buffer size and wrap_content would be measured as big as the
        // buffer; match_parent lets Android stretch the buffer over the whole screen.
        surface.setLayoutParams(new RelativeLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        // The view's own size is the truth after a rotation (display metrics can still describe the
        // old orientation in onConfigurationChanged), so the buffer is sized from each layout.
        surface.addOnLayoutChangeListener(new View.OnLayoutChangeListener() {
            @Override
            public void onLayoutChange(View v, int left, int top, int right, int bottom,
                                       int oldLeft, int oldTop, int oldRight, int oldBottom) {
                applyRenderSize(surface, right - left, bottom - top);
            }
        });
        return surface;
    }

    /** The short side of the buffer is renderHeight pixels in either orientation. */
    private void applyRenderSize(SDLSurface surface, int width, int height) {
        if (width <= 0 || height <= 0) {
            return;
        }
        int wanted = renderHeight();
        int shortSide = Math.min(width, height);
        if (wanted > 0 && shortSide > wanted) {
            float scale = (float) wanted / shortSide;
            surface.getHolder().setFixedSize(Math.round(width * scale), Math.round(height * scale));
        } else {
            // Native resolution: let the surface follow the view again.
            surface.getHolder().setSizeFromLayout();
        }
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
