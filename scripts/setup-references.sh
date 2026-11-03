#!/usr/bin/env bash
# Restore everything this repo expects but does not track: the pinned upstream
# checkouts in references/, the two analysis CLIs (rea, craft-anything-cli), and
# a Chromium build for their browser tools.
#
# Idempotent — re-running leaves an existing checkout alone and skips an
# already-installed piece. Works on Linux and macOS; on Windows use WSL.
#
#   ./scripts/setup-references.sh              # everything
#   SKIP_BROWSER=1 ./scripts/setup-references.sh   # skip the ~120 MB browser
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_DIR="$REPO_ROOT/references"
BIN_DIR="$HOME/.local/bin"
PLAYWRIGHT_CACHE="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"

SUPERPOWERS_REPO="https://github.com/obra/superpowers.git"
SUPERPOWERS_SHA="2ce8aa15d05bd57213e6f746f953aafb7ded7a8b"   # v7.0.1

REA_REPO="https://github.com/morluto/rea.git"
REA_SHA="26b033d51fd627af0cfdf47efcbdb346484e1c85"            # rea-agents 6.8.0
REA_VERSION="6.8.0"

CRAFT_REPO="https://github.com/storytold/craft-anything.git"
CRAFT_SHA="2e0d0813e0b46b1f5ef73b51d501c9f1309dff36"          # v0.3.0
CRAFT_VERSION="0.3.0"
CRAFT_RELEASES="https://github.com/storytold/craft-anything/releases/download/v$CRAFT_VERSION"

OS="$(uname -s)"
ARCH="$(uname -m)"

clone_pinned() { # url dir sha label
  local url="$1" dir="$2" sha="$3" label="$4"
  if [ -d "$dir/.git" ]; then
    printf 'ok   %s already at %s\n' "$label" "$(git -C "$dir" rev-parse --short HEAD)"
    return 0
  fi
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  # GitHub serves commits by SHA, so this pins without downloading history.
  if ! git -C "$dir" fetch -q --depth 1 origin "$sha" 2>/dev/null; then
    git -C "$dir" fetch -q --depth 1 origin HEAD
  fi
  git -C "$dir" checkout -q FETCH_HEAD
  printf 'ok   %s at %s\n' "$label" "$(git -C "$dir" rev-parse --short HEAD)"
}

echo "== reference checkouts =="
clone_pinned "$SUPERPOWERS_REPO" "$REF_DIR/superpowers" "$SUPERPOWERS_SHA" "superpowers"
clone_pinned "$REA_REPO" "$REF_DIR/rea" "$REA_SHA" "rea"
clone_pinned "$CRAFT_REPO" "$REF_DIR/craft-anything" "$CRAFT_SHA" "craft-anything"

echo
echo "== CLIs =="
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

if command -v rea >/dev/null 2>&1; then
  printf 'ok   rea %s\n' "$(rea --version 2>/dev/null | head -1)"
else
  NPM_PREFIX="$(npm config get prefix 2>/dev/null || echo /usr/local)"
  if [ -w "$NPM_PREFIX/lib/node_modules" ] || [ -w "$NPM_PREFIX/lib" ]; then
    npm install --global "rea-agents@$REA_VERSION"
  else
    # Stock Node installs (nvm, Homebrew, system) are not writable unprivileged.
    npm install --global --prefix "$HOME/.local" "rea-agents@$REA_VERSION"
  fi
  printf 'ok   rea %s installed into %s\n' "$REA_VERSION" "$BIN_DIR"
fi

CRAFT_BIN="$BIN_DIR/craft-anything-cli"
if [ -x "$CRAFT_BIN" ]; then
  printf 'ok   %s\n' "$("$CRAFT_BIN" --version 2>/dev/null | head -1)"
else
  CRAFT_TMP="$(mktemp -d)"
  case "$OS" in
    Linux)
      case "$ARCH" in
        x86_64|amd64) CRAFT_ARCH="x86_64" ;;
        aarch64|arm64) CRAFT_ARCH="aarch64" ;;
        *) CRAFT_ARCH="" ;;
      esac
      if [ -n "$CRAFT_ARCH" ]; then
        # Linux ships no CLI-only archive; the binary lives inside the app bundle.
        curl -fsSL -o "$CRAFT_TMP/craft.tar.gz" \
          "$CRAFT_RELEASES/craft-anything-$CRAFT_VERSION-linux-$CRAFT_ARCH.tar.gz"
        tar -xzf "$CRAFT_TMP/craft.tar.gz" -C "$CRAFT_TMP"
        cp "$CRAFT_TMP/craft-anything-$CRAFT_VERSION-linux-$CRAFT_ARCH/bin/craft-anything-cli" "$CRAFT_BIN"
      fi
      ;;
    Darwin)
      # macOS does publish a standalone CLI build.
      curl -fsSL -o "$CRAFT_TMP/craft.zip" \
        "$CRAFT_RELEASES/craft-anything-cli-$CRAFT_VERSION-macos-universal.zip"
      unzip -q "$CRAFT_TMP/craft.zip" -d "$CRAFT_TMP"
      CRAFT_SRC="$(find "$CRAFT_TMP" -type f -name craft-anything-cli | head -1)"
      if [ -n "$CRAFT_SRC" ]; then cp "$CRAFT_SRC" "$CRAFT_BIN"; fi
      ;;
    *)
      echo "!! no prebuilt craft-anything CLI for $OS; use WSL or build from source (Rust 1.97+)" >&2
      ;;
  esac
  if [ -x "$CRAFT_BIN" ]; then
    chmod +x "$CRAFT_BIN"
    printf 'ok   %s\n' "$("$CRAFT_BIN" --version 2>/dev/null | head -1)"
  else
    echo "!! craft-anything-cli was not installed (see message above)" >&2
  fi
  rm -rf "$CRAFT_TMP"
fi

echo
echo "== browser (for web capture and site analysis) =="
CHROMIUM_DEPS="$HOME/.local/lib/chromium-deps"
CHROMIUM_LIB_DIR="$CHROMIUM_DEPS/usr/lib/x86_64-linux-gnu"

find_system_chromium() {
  local candidate
  for candidate in chromium chromium-browser google-chrome google-chrome-stable; do
    command -v "$candidate" && return 0
  done
  return 1
}

# An unprivileged Linux container cannot run `playwright install-deps`, so unpack
# the shared libraries the browser needs into the user prefix instead. The apt
# state is user-owned; nothing here needs root.
install_linux_browser_libs() {
  local apt_dir="$HOME/.apt" tmp found=0 deb
  mkdir -p "$apt_dir/lists/partial" "$apt_dir/etc" "$apt_dir/cache/archives/partial"
  [ -f "$apt_dir/etc/sources.list" ] || printf '%s\n%s\n' \
    'deb http://archive.ubuntu.com/ubuntu noble main universe' \
    'deb http://archive.ubuntu.com/ubuntu noble-updates main universe' > "$apt_dir/etc/sources.list"
  tmp="$(mktemp -d)"
  (
    cd "$tmp" || exit 1
    apt-get -o Dir::State::lists="$apt_dir/lists" \
      -o Dir::State::status=/var/lib/dpkg/status \
      -o Dir::Etc::sourcelist="$apt_dir/etc/sources.list" \
      -o Dir::Etc::sourceparts=/dev/null \
      -o Dir::Cache="$apt_dir/cache" \
      -o APT::Get::List-Cleanup=0 -o Acquire::Check-Valid-Until=false \
      download libnspr4 libnss3 libsqlite3-0 libatk1.0-0t64 libatk-bridge2.0-0t64 \
      libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxkbcommon0 \
      libasound2t64 libatspi2.0-0t64 libxrender1 libxi6 >/dev/null 2>&1
  ) || { rm -rf "$tmp"; return 1; }
  for deb in "$tmp"/*.deb; do
    [ -e "$deb" ] || continue
    dpkg -x "$deb" "$CHROMIUM_DEPS" && found=1
  done
  rm -rf "$tmp"
  [ "$found" = 1 ]
}

# Craft Anything (and Playwright, if pointed at it) needs a binary on PATH, and
# the loader needs to find the unpacked libraries.
write_chromium_wrapper() {
  local shell_bin
  shell_bin="$(find "$PLAYWRIGHT_CACHE" -type f -name chrome-headless-shell 2>/dev/null | head -1)"
  [ -n "$shell_bin" ] || return 1
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/chromium" <<WRAP
#!/usr/bin/env bash
# Generated by scripts/setup-references.sh: Playwright's headless Chrome with
# user-unpacked shared libraries.
export LD_LIBRARY_PATH="$CHROMIUM_LIB_DIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$shell_bin" "\$@"
WRAP
  chmod +x "$BIN_DIR/chromium"
}

if [ -n "${SKIP_BROWSER:-}" ]; then
  echo "skipped (SKIP_BROWSER set)"
elif find_system_chromium >/dev/null 2>&1; then
  printf 'ok   browser: %s\n' "$("$(find_system_chromium)" --version 2>/dev/null | head -1)"
else
  if ! compgen -G "$PLAYWRIGHT_CACHE/chromium*" >/dev/null 2>&1; then
    npx --yes playwright@latest install chromium
  fi
  SHELL_BIN="$(find "$PLAYWRIGHT_CACHE" -type f -name chrome-headless-shell 2>/dev/null | head -1)"
  if [ -n "$SHELL_BIN" ] && ! LD_LIBRARY_PATH="$CHROMIUM_LIB_DIR" "$SHELL_BIN" --version >/dev/null 2>&1; then
    if [ "$OS" = "Linux" ] && install_linux_browser_libs && write_chromium_wrapper; then
      printf 'ok   unpacked browser libs into %s, wrapper at %s\n' "$CHROMIUM_DEPS" "$BIN_DIR/chromium"
    else
      echo "!! browser cannot launch; with root run: sudo npx playwright install-deps chromium" >&2
    fi
  fi
  if command -v chromium >/dev/null 2>&1; then
    printf 'ok   browser: %s\n' "$(chromium --version 2>&1 | head -1)"
  fi
fi

echo
echo "== MCP registration =="
echo "Servers are declared in .mcp.json (project scope). Clients that read it pick"
echo "both up automatically; otherwise register manually:"
echo "  rea mcp add          # writes REA into your client's config"
echo "  craft-anything-cli mcp --help"
echo "Verify with: node scripts/check-mcp.mjs"

echo
echo "== vendored skills =="
printf 'ok   %s skill(s) in .agents/skills\n' "$(find "$REPO_ROOT/.agents/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
