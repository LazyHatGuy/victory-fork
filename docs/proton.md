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
rustup target add x86_64-pc-windows-gnu --toolchain 1.98.1   # links victory.exe
rustup target add x86_64-pc-windows-msvc --toolchain 1.98.1  # compile-checks the MSVC tree

# build
cargo win        # alias: build -p victory --target x86_64-pc-windows-gnu --release
                 # lands at target/x86_64-pc-windows-gnu/release/victory.exe
```

`cargo win-check` (`check --workspace --all-targets --target
x86_64-pc-windows-msvc`) type-checks the tree exactly as the Windows CI
builds it, without needing an MSVC linker — worth running before pushing.

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

Expected to work as on Windows (the file-side commands never touch the GPU):

- `config`, `inspect`, `census`, `lib-exports`, `shader-info`.
- `victory config` and `victory run` print a `host Wine <version>` line when
  the ntdll under them is Wine's, so logs say which host produced them.

Expected for `run`: victory creates its device through the prefix's
`d3d12.dll` (vkd3d-proton). `dxil.dll`'s validator stays optional — under
Wine it is usually absent, which the code already tolerates.

Known gaps and unverified areas (file an issue if you hit one):

- **Shader validation**: `DxcCreateInstance` needs dxcompiler — Wine has no
  DXC. Translation output skips validation as it does on Windows without
  `dxil.dll`; treat translation results under Wine as unvalidated.
- **Diagnostics build** (`--features diagnostics`, `--diagnostics-impls`):
  the write-watch queries and the debug layer have had no Wine testing.
- **Input/audio**: hle's gamepad and audio paths were built against Windows
  behaviour; under Wine they ride whatever Wine presents. Unverified.
- **HDR/10-bit output**: untested under vkd3d-proton.

## 5. CI

The Ubuntu job runs the native Linux test suite; the Windows job runs the
same suite plus clippy. Nothing in CI exercises the Proton path — this page
is the procedure, and `proton/run.sh config` is the smoke test to run before
reporting anything.
