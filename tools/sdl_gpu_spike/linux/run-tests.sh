#!/bin/sh
# Runs the spike's checks inside the Linux container (see Dockerfile).
#
# Expects in /corpus:
#   bundled.tsv, corpus.tsv, leftover.tsv  manifests with /src and /corpus paths
#   texture.bmp                            default texture for the render sweeps
# Writes results (not images) to /corpus/linux-results. Progress goes to
# stderr. With /corpus not shareable (colima only shares $HOME), stream it:
#   tar -C <corpus> -cf - . | docker run -i --rm -v $PWD:/src:ro oolite-gpu-spike \
#       sh -c 'mkdir /corpus && tar -xf - -C /corpus && /src/tools/sdl_gpu_spike/linux/run-tests.sh \
#       && tar -cf - -C /corpus linux-results' | tar -xf - -C <corpus>
set -eu
exec 3>&1 1>&2

out=/corpus/linux-results
mkdir -p "$out"
meson setup /build /src/tools/sdl_gpu_spike >/dev/null
meson compile -C /build >/dev/null

Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
export DISPLAY=:99 SDL_VIDEO_DRIVER=x11 SDL_GPU_DRIVER=vulkan
sleep 2
glxinfo -B 2>/dev/null | grep -E "OpenGL renderer|compatibility profile version" || true

for manifest in bundled corpus leftover; do
    /build/oogpu-check "/corpus/$manifest.tsv" "$out/check-$manifest.log" >"$out/check-$manifest.tsv" 2>"$out/check-$manifest.err" || true
    echo "check $manifest: $(grep -E 'driver|programs passed' "$out/check-$manifest.err" | tr '\n' ' ')"
done

for manifest in bundled corpus leftover; do
    for value in 0.5 1; do
        python3 /src/tools/sdl_gpu_spike/corpus/sweep.py /build/oogpu-render "/corpus/$manifest.tsv" \
            "/tmp/images-$manifest-$value" /corpus/texture.bmp "$value" >"$out/sweep-$manifest-$value.tsv"
        echo "sweep $manifest $value: $(cut -f1 "$out/sweep-$manifest-$value.tsv" | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
    done
done
