#!/usr/bin/env bash
# Build the x86_64 GLib/GStreamer runtime used by winegstreamer.
#
# The default profile intentionally remains small.  `full-video` adds the
# video-capable plugin set used by the CX25 OEM runtime without requiring an
# unrelated FFmpeg build (gst-libav is therefore still disabled).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CX_VERSION=26
INSTALL_DEPS=0
MEDIA_PROFILE=minimal
MEDIA_INSTALL_ARG=""
MEDIA_INSTALL_WAS_EXPLICIT="${MEDIA_INSTALL+x}"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cx) CX_VERSION="$2"; shift ;;
    --profile) MEDIA_PROFILE="$2"; shift ;;
    --full-video) MEDIA_PROFILE=full-video ;;
    --media-install) MEDIA_INSTALL_ARG="$2"; shift ;;
    --jobs) JOBS="$2"; shift ;;
    --install-deps) INSTALL_DEPS=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--cx 26] [--profile minimal|full-video]"
      echo "       [--full-video] [--media-install PATH] [--install-deps] [--jobs N]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

[[ "$CX_VERSION" == 26 ]] || {
  echo "The media build is currently validated only with CX26." >&2
  exit 1
}
case "$MEDIA_PROFILE" in
  minimal|full-video) ;;
  *)
    echo "Unknown media profile: $MEDIA_PROFILE (expected minimal or full-video)." >&2
    exit 1
    ;;
esac

export CX_VERSION
source "$SCRIPT_DIR/env-x86_64.sh"

# Keep the existing minimal install untouched.  A full-video build gets its
# own default prefix unless the caller deliberately supplied MEDIA_INSTALL or
# --media-install, so both profiles can coexist for regression comparisons.
if [[ -n "$MEDIA_INSTALL_ARG" ]]; then
  export MEDIA_INSTALL="$MEDIA_INSTALL_ARG"
elif [[ -z "$MEDIA_INSTALL_WAS_EXPLICIT" && "$MEDIA_PROFILE" == full-video ]]; then
  export MEDIA_INSTALL="$OGOM/install/media-cx${CX_VERSION}-full-video-x86_64"
fi
"$SCRIPT_DIR/prepare-build-deps.sh" --cx "$CX_VERSION"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
MIN_FLAG="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"

if [[ "$INSTALL_DEPS" -eq 1 ]]; then
  # meson/ninja/bison/pkgconf are build-only (bottles OK).
  brew_x86 install meson ninja bison pkgconf
  # pcre2/libffi are linked into the media dylibs that get bundled.
  brew_x86_install_runtime pcre2 libffi
fi

MESON="$HOMEBREW_PREFIX/bin/meson"
NINJA="$HOMEBREW_PREFIX/bin/ninja"
SYSTEM_PYTHON=/usr/bin/python3
MESON_PACKAGE="$(find "$HOMEBREW_PREFIX/lib" -type d -path '*/site-packages/mesonbuild' -print -quit 2>/dev/null || true)"
PYTHON_SITE="${MESON_PACKAGE%/mesonbuild}"
GLIB_SRC="$BUILD_DIR/cx$CX_VERSION/sources/glib"
GST_SRC="$BUILD_DIR/cx$CX_VERSION/sources/gstreamer"
MEDIA_BUILD="$BUILD_DIR/cx$CX_VERSION/media-$MEDIA_PROFILE"

for required in "$MESON" "$NINJA" "$SYSTEM_PYTHON"; do
  [[ -x "$required" ]] || { echo "Missing build tool: $required" >&2; exit 1; }
done
[[ -n "$MESON_PACKAGE" ]] || {
  echo "Cannot locate Homebrew mesonbuild Python package below $HOMEBREW_PREFIX/lib" >&2
  exit 1
}
for required in "$GLIB_SRC/meson.build" "$GST_SRC/meson.build"; do
  [[ -f "$required" ]] || { echo "Missing CrossOver source: $required" >&2; exit 1; }
done

# CrossOver's GLib source archive omits this pinned submodule.
if [[ ! -f "$GLIB_SRC/subprojects/gvdb/meson.build" ]]; then
  mkdir -p "$GLIB_SRC/subprojects"
  git clone https://gitlab.gnome.org/GNOME/gvdb.git "$GLIB_SRC/subprojects/gvdb"
  git -C "$GLIB_SRC/subprojects/gvdb" checkout 0854af0fdb6d527a8d1999835ac2c5059976c210
fi

BUILD_PATH="$HOMEBREW_PREFIX/opt/bison/bin:/usr/bin:/bin:/usr/sbin:/sbin:$MEDIA_INSTALL/bin:$HOMEBREW_PREFIX/bin"
PC_PATH="$MEDIA_INSTALL/lib/pkgconfig:$HOMEBREW_PREFIX/lib/pkgconfig:$HOMEBREW_PREFIX/opt/libffi/lib/pkgconfig:$HOMEBREW_PREFIX/opt/pcre2/lib/pkgconfig"
MESON_CMD=(
  arch -x86_64 env
  PATH="$BUILD_PATH"
  PYTHONPATH="$PYTHON_SITE"
  PKG_CONFIG="$HOMEBREW_PREFIX/bin/pkg-config"
  PKG_CONFIG_PATH="$PC_PATH"
  DYLD_LIBRARY_PATH="$MEDIA_INSTALL/lib"
  MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"
  CFLAGS="${CFLAGS:+$CFLAGS }$MIN_FLAG"
  CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }$MIN_FLAG"
  LDFLAGS="${LDFLAGS:+$LDFLAGS }$MIN_FLAG"
  "$SYSTEM_PYTHON" "$MESON"
)

mkdir -p "$MEDIA_BUILD" "$MEDIA_INSTALL"

GLIB_SETUP_ARGS=(
  --prefix="$MEDIA_INSTALL" --libdir=lib --buildtype=release
  -Ddefault_library=shared -Dtests=false -Dinstalled_tests=false -Dnls=disabled
  -Dman=false -Dgtk_doc=false -Dlibmount=disabled -Dselinux=disabled -Dxattr=false
  -Dbsymbolic_functions=false
  -Dc_args="$MIN_FLAG" -Dcpp_args="$MIN_FLAG"
  -Dc_link_args="$MIN_FLAG" -Dcpp_link_args="$MIN_FLAG"
)
if [[ -f "$MEDIA_BUILD/glib-build/build.ninja" ]]; then
  "${MESON_CMD[@]}" setup --reconfigure "$MEDIA_BUILD/glib-build" "$GLIB_SRC" "${GLIB_SETUP_ARGS[@]}"
else
  "${MESON_CMD[@]}" setup "$MEDIA_BUILD/glib-build" "$GLIB_SRC" "${GLIB_SETUP_ARGS[@]}"
fi
"${MESON_CMD[@]}" compile -C "$MEDIA_BUILD/glib-build" -j "$JOBS"
"${MESON_CMD[@]}" install -C "$MEDIA_BUILD/glib-build"

GST_ARGS=(
  -Ddefault_library=shared -Dauto_features=disabled -Dbuild-tools-source=system
  -Ddevtools=disabled -Dges=disabled -Drtsp_server=disabled -Dpython=disabled
  -Dtls=disabled -Dlibnice=disabled -Dtests=disabled
  -Dexamples=disabled -Dintrospection=disabled -Dnls=disabled -Dorc=disabled
  -Ddoc=disabled -Dgtk_doc=disabled
)

case "$MEDIA_PROFILE" in
  minimal)
    GST_ARGS+=(
      -Dbase=enabled -Dgood=disabled -Dugly=disabled -Dbad=disabled -Dlibav=disabled
      -Dtools=disabled
    )
    ;;
  full-video)
    # This is the OEM25-equivalent media set.  Keep optional dependencies
    # disabled and name every required plugin explicitly so the build remains
    # deterministic and does not accidentally pull in host Homebrew codecs.
    GST_ARGS+=(
      -Dbase=enabled -Dgood=enabled -Dugly=enabled -Dbad=enabled -Dlibav=disabled
      -Dtools=enabled
      -Dgst-plugins-base:app=enabled
      -Dgst-plugins-base:audioconvert=enabled
      -Dgst-plugins-base:audioresample=enabled
      -Dgst-plugins-base:gl=enabled
      -Dgst-plugins-base:gl_api=opengl
      -Dgst-plugins-base:gl-graphene=disabled
      -Dgst-plugins-base:gl_platform=cgl
      -Dgst-plugins-base:gl_winsys=cocoa
      -Dgst-plugins-base:pbtypes=enabled
      -Dgst-plugins-base:playback=enabled
      -Dgst-plugins-base:subparse=enabled
      -Dgst-plugins-base:typefind=enabled
      -Dgst-plugins-base:videoconvertscale=enabled
      -Dgst-plugins-base:videorate=enabled
      -Dgst-plugins-base:volume=enabled
      -Dgst-plugins-good:audioparsers=enabled
      -Dgst-plugins-good:avi=enabled
      -Dgst-plugins-good:deinterlace=enabled
      -Dgst-plugins-good:id3demux=enabled
      -Dgst-plugins-good:isomp4=enabled
      -Dgst-plugins-good:videofilter=enabled
      -Dgst-plugins-good:wavparse=enabled
      -Dgst-plugins-bad:applemedia=enabled
      -Dgst-plugins-bad:gl=enabled
      -Dgst-plugins-bad:videoparsers=enabled
      -Dgst-plugins-ugly:asfdemux=enabled
    )
    ;;
esac

GST_SETUP_ARGS=(
  --prefix="$MEDIA_INSTALL" --libdir=lib --buildtype=release
  "${GST_ARGS[@]}"
  -Dc_args="$MIN_FLAG" -Dcpp_args="$MIN_FLAG"
  -Dc_link_args="$MIN_FLAG" -Dcpp_link_args="$MIN_FLAG"
)
if [[ -f "$MEDIA_BUILD/gstreamer-build/build.ninja" ]]; then
  "${MESON_CMD[@]}" setup --reconfigure "$MEDIA_BUILD/gstreamer-build" "$GST_SRC" "${GST_SETUP_ARGS[@]}"
else
  "${MESON_CMD[@]}" setup "$MEDIA_BUILD/gstreamer-build" "$GST_SRC" "${GST_SETUP_ARGS[@]}"
fi
"${MESON_CMD[@]}" compile -C "$MEDIA_BUILD/gstreamer-build" -j "$JOBS"
"${MESON_CMD[@]}" install -C "$MEDIA_BUILD/gstreamer-build"

MEDIA_PC=(gstreamer-1.0 gstreamer-base-1.0 gstreamer-audio-1.0)
MEDIA_PLUGINS=(libgstcoreelements.dylib)
if [[ "$MEDIA_PROFILE" == full-video ]]; then
  MEDIA_PC+=(gstreamer-video-1.0 gstreamer-pbutils-1.0)
  MEDIA_PLUGINS+=(
    libgstapplemedia.dylib
    libgstasf.dylib
    libgstaudioconvert.dylib
    libgstaudioparsers.dylib
    libgstaudioresample.dylib
    libgstavi.dylib
    libgstdeinterlace.dylib
    libgstid3demux.dylib
    libgstisomp4.dylib
    libgstopengl.dylib
    libgstplayback.dylib
    libgsttypefindfunctions.dylib
    libgstvideoconvertscale.dylib
    libgstvideofilter.dylib
    libgstvideoparsersbad.dylib
    libgstwavparse.dylib
  )
fi

for pc in "${MEDIA_PC[@]}"; do
  arch -x86_64 env PKG_CONFIG_PATH="$MEDIA_INSTALL/lib/pkgconfig" \
    "$HOMEBREW_PREFIX/bin/pkg-config" --exists "$pc" || {
      echo "Media stack validation failed: $pc" >&2
      exit 1
    }
done

for plugin in "${MEDIA_PLUGINS[@]}"; do
  [[ -f "$MEDIA_INSTALL/lib/gstreamer-1.0/$plugin" ]] || {
    echo "Media stack validation failed: missing plugin $plugin" >&2
    exit 1
  }
done

if [[ "$MEDIA_PROFILE" == full-video ]]; then
  [[ -x "$MEDIA_INSTALL/libexec/gstreamer-1.0/gst-plugin-scanner" ]] || {
    echo "Media stack validation failed: missing gst-plugin-scanner" >&2
    exit 1
  }
fi

echo "${MEDIA_PROFILE} CX$CX_VERSION media stack installed: $MEDIA_INSTALL"
