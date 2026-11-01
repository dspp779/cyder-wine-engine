# BlueCG final bitmap GPU experiment

This helper is an opt-in experiment for the patched GDI32 hook. It is not
installed or packed by the normal engine build. The default GDI path and other
executables do not load it.

Build both PE architectures from the engine repository:

```sh
bash tools/bluecg-gpu-blit/build.sh /path/to/new-private-output
```

Use an isolated, backed-up test prefix only. Install the i386 DLL as
`drive_c/windows/syswow64/cyder_bluecg_gpu.dll` and the x86_64 DLL as
`drive_c/windows/system32/cyder_bluecg_gpu.dll`, refusing existing files.
Generate the color LUT from an unfiltered native screenshot with an embedded
output ICC profile (requires Pillow/ImageCms):

```sh
python3 tools/bluecg-gpu-blit/make-color-lut.py \
  --capture /path/to/native-capture.png --output /path/to/new-color.lut
```

Copy the same LUT alongside both helper DLLs as `cyder_bluecg_gpu.dll.lut`.
It converts filtered sRGB values to the fixed capture/display output profile
through a 33³ GPU lookup texture. It is generated once, not per frame, and does
not change OS color settings. A missing/invalid LUT rejects the GPU path. Keep
the display/profile fixed; regenerate and revalidate after a profile change.
Remove only these files after stopping that prefix and verifying their hashes.
Do not put them in the game directory or production shared bottle.

Set `CYDER_BLUECG_BLIT_FILTER=gpu-linear` only in the BlueCG launch environment.
`gpu-nearest` is a positive control for the GPU presentation route. `halftone`
selects the preceding CPU experiment; unset the variable for the original path.
The GPU hook accepts only `bluecg.exe`, its own full client, SRCCOPY, an
untransformed destination DC and the tested 961×721 source bitmap. The destination
must actually be resized. Printing, EMF, memory destinations, other dimensions
and partial target rectangles stay on their original GDI path.

The helper stages a 1:1 GDI copy in top-down BGRA, uploads to one reusable texture,
and applies the output-profile 3D LUT in a fragment shader and draws through an independent double-buffered OpenGL child window with
GL_LINEAR and clamp-to-edge. It aligns the texture origin to Wine HALFTONE's
source-origin convention. The child returns HTTRANSPARENT and does not activate.
The original parent pixel format is untouched. The prior thread GL context/DC
is restored. Child destruction frees texture/context/DC/staging resources. Full
client GDI fallback hides the child; a later eligible blit shows it again.
Presentation failure falls back to the original StretchBlt. A formal GPU run
must reject any fallback or mixed API stream instead of calling it GPU output.

With `CYDER_GDI_PROFILE_DIR`, the helper logs the actual GL renderer, verified
sampler, upload route and final frame/error counts. GDI profile `api=3` marks a
successful GPU final-bitmap submission; `stretch_mode` still describes the
caller's GDI DC and is not the GPU sampler. These are submission intervals, not
GPU completion or display scanout. The texture upload, context switches and swap
are part of the measured GPU-path cost. Swap interval is zero; game pacing stays
with the game. Keep the same game, scene, source size, client size, observers,
power collector and power mode across comparisons.

This prototype does not accelerate arbitrary GDI, guarantee GDI readback of the
GPU child, change DPI/Retina settings, or enable a policy for other games.
