# Running victory on Linux under Proton

The Linux host runs the tools, the tests and the analysis commands natively.
Actually *running the title* needs a Windows process environment with real
D3D12 — which Proton provides: Wine's loader plus dxvk/vkd3d-proton giving
the GPU stack. So the supported Linux path is: **build `victory.exe` here,
run it inside a Proton prefix.** The title then loads inside that process
exactly as it does on Windows.

Everything below is the full command list for an Arch box; adapt package
names for your distro.

## 1. Build the Windows binary on Linux

```bash
# toolchains
sudo pacman -S --needed rustup mingw-w64-gcc mingw-w64-winpthreads

# the toolchain pinned in rust-toolchain.toml, plus the Windows targets
rustup toolchain install 1.98.1
rustup target add x86_64-pc-windows-gnu --toolchain 1.98.1   # builds and links victory.exe

# build
cargo win        # alias: build -p victory --target x86_64-pc-windows-gnu --release
                 # lands at target/x86_64-pc-windows-gnu/release/victory.exe
```

`cargo win-check` (`check --workspace --all-targets --target
x86_64-pc-windows-gnu`) type-checks the whole Windows tree — tests included
— on the Linux box. A true MSVC-target check needs `clang`/`lld` (or a
Windows box), so the Windows CI job remains that check.

## 2. Run it under Proton

Install a Proton build under Steam's compatibility tools (GE-Proton works
well here), then:

```bash
proton/run.sh config                       # smoke test: prints resolved paths
proton/run.sh --z /mnt/games inspect "Z:\\games\\scripts\\x64\\final.js.c.c.gmpc"
proton/run.sh --z /mnt/games run "Z:\\games\\x64\\final.exe" --execute
```

`proton/run.sh` picks the newest `GE-Proton*` it can find, keeps its prefix
at `$XDG_DATA_HOME/victory/proton` (idempotent), and takes `--prefix`,
`--exe`, `--proton` (a specific Proton dir or plain `wine`), `--z` and
`--config`. `--z DIR` links a folder into the prefix's Z: drive, so a game
directory stays wherever it lives while the config can name it `Z:\games`.

## 3. The config for a Proton run

`victory.toml` is read from the process' working directory, and Wine
resolves the Unix cwd through its own Z: mapping — so relative config names
work on both sides. Windows paths inside the file, however, must be Windows
paths. Keep a second, git-ignored config:

```bash
cp victory.example.toml victory.proton.toml
```

```toml
[paths]
game_dir = 'Z:\games'
# cache_dir/data_dir default to the prefix's LOCALAPPDATA, which is fine;
# or point them at Z:\somewhere for easy browsing from the Linux side.
```

and pass `--config victory.proton.toml`. The asset-policy rules are
unchanged: data lives outside the repo, and `cargo xtask policy` still
insists on it.

## 4. What works, what is Wine-dependent

Verified 2026-11-24 on GE-Proton11-11 (Wine 11.0 staging, dxvk/vkd3d-proton
synced into the prefix as native DLLs, `ntsync` kernel driver):

- `proton/smoke.sh` passes: `config` resolves and prints the `host Wine`
  banner, the title directory is reachable through the prefix, and `census`
  runs against it.
- The whole `victory-gpu` test suite runs as a Windows binary under the same
  prefix: **106 of 111 pass**, covering device creation, the newer device
  levels, fences, heaps, copies and queue submission — i.e. Proton really
  does provide the D3D12 ground victory hosts on. The four failures:
  - `indirect::tests::argument_clamp_builds` and
    `host_list_reuses_and_grows_scratch_across_submissions`: `D3DCompile`
    of a `cs_5_1` kernel. Wine's built-in `d3dcompiler_47` and the June-2010
    native one (`winetricks d3dcompiler_47`) both reject the 5_1 profile; a
    Win10-SDK-era native `d3dcompiler_47` is what that path needs.
  - `pipeline::library::tests::a_rejected_blob_gives_an_empty_library`:
    vkd3d-proton errors on `OpenPipelineLibrary` of a garbage blob where
    real D3D12 hands back an empty library.
  - `resource::tests::a_depth_planes_twin_is_drawn_into_the_plane`: the
    depth-plane twin pipeline fails creation under vkd3d (`0x8876086C`).

Known gaps and unverified areas (file an issue if you hit one):

- **Shader validation**: `DxcCreateInstance` needs dxcompiler — Wine has no
  DXC. Translation output skips validation as it does on Windows without
  `dxil.dll`; treat translation results under Wine as unvalidated.
- **Diagnostics build** (`--features diagnostics`, `--diagnostics-impls`):
  the write-watch queries and the debug layer have had no Wine testing.
- **Input/audio**: hle's gamepad and audio paths were built against Windows
  behaviour; under Wine they ride whatever Wine presents. Unverified.
- **HDR/10-bit output**: untested under vkd3d-proton.
- A full `victory run` of the title under Proton has not been attempted yet.

## 5. Tests and CI

The Ubuntu job runs the native Linux test suite; the Windows job runs the
same suite plus clippy. `cargo test -p xtask` checks the launch scripts
parse and their usage text holds; `proton/smoke.sh` is the Proton-path
smoke test — run it after touching `proton/`, and paste its output into
bug reports.
