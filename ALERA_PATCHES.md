# Alera patches

This fork is consumed by Alera as a Git submodule while the terminal dependency
fixes are reviewed upstream.

## Fork metadata

- Fork: <https://github.com/leynier/dart_terminal.git>
- Stable branch: `master`
- Upstream: <https://github.com/kingwill101/dart_terminal>
- Upstream pull request: <https://github.com/kingwill101/dart_terminal/pull/15>

## Changes

- Recognize Puro pub cache paths in the `ghostty_vte` build hook so local Puro
  Flutter/Dart installs resolve prebuilts correctly.
- Allow vendored VTE packages to use prebuilt native libraries when consumed
  from a downstream repository or submodule.
- Stage bundled Ghostty source patches in hook-owned output so builds never
  modify the nested source checkout.
- Build Android VTE artifacts with portable emulated TLS and reject incompatible
  `__tls_get_addr` dependencies before release.

## Why Alera carries this fork

Alera vendors `ghostty_vte` through this submodule so terminal dependencies can
remain reproducible while upstream fixes are pending or being released. The
fork avoids downstream patch files and publishes verified prebuilts from its
stable branch.
