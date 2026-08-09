#!/usr/bin/env bash
# E-7 / R2 — is iOS Picture-in-Picture reachable without forking
# `media_kit_video`? (docs/risks.md R2, SPEC §8 R2)
#
# `AVPictureInPictureController` needs an `AVPlayerLayer` or an
# `AVSampleBufferDisplayLayer`. media_kit_video renders into a Flutter texture,
# so the question is narrower than "is PiP possible": it is whether the decoded
# frame is REACHABLE from code we are allowed to write.
#
# This is a static read rather than a run, and it is a script rather than a
# paragraph so that an upstream bump is checked rather than assumed. Each
# assertion prints REACHABLE or SEALED; the verdict is the conjunction.
#
# Usage: tool/spikes/e7_ios_pip_reachability.sh [path to media_kit_video]
set -uo pipefail

PKG="${1:-$HOME/.pub-cache/hosted/pub.dev/media_kit_video-2.0.1}"
IOS="$PKG/ios/Classes/plugin"
[ -d "$IOS" ] || { echo "FATAL: no media_kit_video iOS sources at $IOS"; exit 2; }

fail=0
say() { # say <label> <expected: REACHABLE|SEALED> <actual>
    if [ "$2" = "$3" ]; then echo "  ok    $1: $3"
    else echo "  CHANGED $1: expected $2, found $3"; fail=1; fi
}

echo "E-7: can app code reach the decoded frame?"

# 1. The frame itself. Both texture implementations hold a CVPixelBuffer and
#    both expose it, so the pixels are not the obstacle.
grep -q 'public let pixelBuffer: CVPixelBuffer' "$IOS/gles/TextureGLESContext.swift" \
  && a=REACHABLE || a=SEALED
say "TextureGLESContext.pixelBuffer" REACHABLE "$a"
grep -q 'public func copyPixelBuffer' "$IOS/TextureHW.swift" && a=REACHABLE || a=SEALED
say "TextureHW.copyPixelBuffer()" REACHABLE "$a"

# 2. Its pixel format, because AVSampleBufferDisplayLayer accepts BGRA.
grep -q 'kCVPixelFormatType_32BGRA' "$IOS/gles/OpenGLESHelpers.swift" \
  && a=REACHABLE || a=SEALED
say "pixel format is 32BGRA" REACHABLE "$a"

# 3. The chain to an INSTANCE, which is where it ends. Every link is private,
#    and the only public entry point is the plugin's `register(with:)`.
grep -qE '^ *private var texture: ResizableTextureProtocol' "$IOS/common/VideoOutput.swift" \
  && a=SEALED || a=REACHABLE
say "VideoOutput.texture" SEALED "$a"
grep -qE '^ *private var videoOutputs' "$IOS/common/VideoOutputManager.swift" \
  && a=SEALED || a=REACHABLE
say "VideoOutputManager.videoOutputs" SEALED "$a"
grep -qE '^ *private let videoOutputManager' "$IOS/common/MediaKitVideoPlugin.swift" \
  && a=SEALED || a=REACHABLE
say "MediaKitVideoPlugin.videoOutputManager" SEALED "$a"

# 4. And no PiP vocabulary anywhere in the package, Dart or Swift — so there is
#    nothing to opt into either.
if grep -rqi 'PictureInPicture\|AVSampleBufferDisplayLayer' "$PKG"; then
    a=REACHABLE; else a=SEALED; fi
say "any PiP API in media_kit_video" SEALED "$a"

echo
if [ "$fail" -eq 0 ]; then
    cat <<'EOF'
VERDICT unchanged: the frame is a CVPixelBuffer and could feed an
AVSampleBufferDisplayLayer, but no instance of the texture is reachable from
outside the plugin. iOS PiP therefore needs a FORK of media_kit_video, plus a
CMSampleBuffer timing layer and an AVPictureInPictureSampleBufferPlaybackDelegate
that this repository would then own. R2 is DECLINED rather than retired, and
SPEC §10's M7 row is worded to F14 — which asks for background audio and
lock-screen controls and does not ask for PiP.

Two second-order obstacles, recorded so a later reader does not think the fork
alone is the cost: the buffers come from a THREE-deep SwappableObjectManager
pool that Flutter's own copyPixelBuffer() recycles, so a layer holding one
competes with the texture that draws the video; and the frames carry no
presentation timestamps, which AVSampleBufferDisplayLayer requires.
EOF
    exit 0
else
    echo "media_kit_video has CHANGED since this spike was written. Re-read"
    echo "the sources named above and re-take the decision before trusting R2."
    exit 1
fi
