package org.katsa.game;

import org.libsdl.app.SDLActivity;

/**
 * The whole app is SDL's activity. SDL loads the libraries in order and calls SDL_main from the last
 * one (libmain.so, built from native/src/katsa_host.c). The Lua runtime then opens SDL2, OpenAL and
 * the katsa_* libraries again with dlopen; the loader returns the copies loaded here.
 */
public class KatsaActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] {
            "SDL2", "openal", "katsa_native", "katsa_box2d", "katsa_net", "main"
        };
    }
}
