# cmp-matrix-test

Claude Code skill that runs the cmpose.dev generator's release matrix (`npm run smoke` in
the private cmpose.dev backend) and reports the result with screenshots.

## Requirements

- A checkout of the cmpose.dev backend (`CMP_BACKEND_DIR`, required, no default;
  set it e.g. in your shell profile) and a local CmpTemplate clone
  next to it (or `CMP_TEMPLATE_REPO`).
- JDK 21, Android SDK with an AVD (`CMP_SMOKE_AVD`, default `Medium_Phone_API_36`) and
  `~/.android/debug.keystore`, Xcode with an iPhone simulator runtime.
- `ffmpeg` for a full run (release screenshots are checked for a dark background).

## Usage

`/cmp-matrix-test` — or ask "matris testini koş", "run the generator matrix on TURKER",
"quick smoke". Direct: `bash scripts/run.sh [--ref <tag|branch> | --dir <path>] [--build-only]`.
