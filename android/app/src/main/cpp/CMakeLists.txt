# Builds the three libraries that Gradle cannot take prebuilt:
#   libSDL2.so    window, GL ES context, input, SDLActivity glue (source in android/deps/SDL2)
#   libopenal.so  OpenAL Soft (source in android/deps/openal-soft)
#   libmain.so    the Katsa host (native/src/host/*.c) linked with a static LuaJIT
# katsa_native, katsa_box2d and katsa_net come from tools/native/build.py android (jniLibs).
cmake_minimum_required(VERSION 3.18)
project(katsa_android C CXX)

get_filename_component(KATSA_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../../.." ABSOLUTE)
set(KATSA_DEPS "${KATSA_ROOT}/android/deps")
set(KATSA_LUAJIT "${KATSA_DEPS}/luajit/${ANDROID_ABI}")

foreach(path IN ITEMS "${KATSA_DEPS}/SDL2/CMakeLists.txt" "${KATSA_DEPS}/openal-soft/CMakeLists.txt"
        "${KATSA_LUAJIT}/lib/libluajit-5.1.a")
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "Missing ${path}. Run: python3 android/prepare.py (see docs/guides/katsa/building.md)")
    endif()
endforeach()

# --- SDL2 ---------------------------------------------------------------------------------------
set(SDL_SHARED ON CACHE BOOL "" FORCE)
set(SDL_STATIC OFF CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
add_subdirectory("${KATSA_DEPS}/SDL2" "${CMAKE_CURRENT_BINARY_DIR}/SDL2")

# --- OpenAL Soft --------------------------------------------------------------------------------
set(LIBTYPE SHARED CACHE STRING "" FORCE)
foreach(option ALSOFT_UTILS ALSOFT_EXAMPLES ALSOFT_TESTS ALSOFT_INSTALL ALSOFT_INSTALL_CONFIG
        ALSOFT_INSTALL_HRTF_DATA ALSOFT_INSTALL_AMBDEC_PRESETS ALSOFT_INSTALL_EXAMPLES
        ALSOFT_INSTALL_UTILS ALSOFT_UPDATE_BUILD_VERSION)
    set(${option} OFF CACHE BOOL "" FORCE)
endforeach()
add_subdirectory("${KATSA_DEPS}/openal-soft" "${CMAKE_CURRENT_BINARY_DIR}/openal-soft")
# Android packages plain lib<name>.so files: drop the version suffix and the libopenal.so.1 SONAME.
set_target_properties(OpenAL PROPERTIES VERSION "" SOVERSION "")

# --- Katsa host -> libmain.so -------------------------------------------------------------------
set(KATSA_HOST "${KATSA_ROOT}/native/src/host")
add_library(main SHARED
    "${KATSA_HOST}/main.c"
    "${KATSA_HOST}/android.c"
    "${KATSA_HOST}/archive.c"
    "${KATSA_HOST}/image.c")
target_include_directories(main PRIVATE
    "${KATSA_DEPS}/SDL2/include"
    "${KATSA_LUAJIT}/include/luajit-2.1")
# SDL_main must stay exported: SDLActivity looks it up with dlsym.
target_link_libraries(main PRIVATE SDL2 "${KATSA_LUAJIT}/lib/libluajit-5.1.a" log dl m)
set_target_properties(main PROPERTIES C_VISIBILITY_PRESET default)
