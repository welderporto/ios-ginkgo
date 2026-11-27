# userland/ credits and licences

- `gpu/` (eagl.c, gl_osmesa.c, redwood_gl.h, topaz_inject.c, bbd_wrap.c) and `mesa/` (Mesa patches,
  `redwood-drm/`): from [MakrSas/ios-topaz](https://github.com/MakrSas/ios-topaz) `userland/`, which is based on
  the HakiOS user space by OOSEX GANG — MIT License, Copyright (c) 2026 OOSEX GANG.
- `tools/mkeagl.py`, `tools/eagl_slots.txt`: from [HakiOS](https://github.com/oosexgang/hackios-xnu-kernel)
  `userland/userland/` (MIT, OOSEX GANG).
- `build-gpu.sh`: this port (ginkgo), adapted from topaz's `mk-mesa-mac.sh` and HakiOS's `build.sh`.
- Mesa 25.0.7 is downloaded at build time from archive.mesa3d.org (MIT and others, see Mesa's docs).

No Apple or Qualcomm binaries are in this directory or in the build's artifact. The GPU firmware
(a610_zap.*, a630_sqe.fw) is copied by the owner from their own phone's /vendor/firmware into the
iOS root at /usr/share/firmware/topaz/ and is never committed.
