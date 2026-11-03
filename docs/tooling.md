# Tooling and reference checkouts

What is installed, what was actually verified, and what each tool still needs.
Everything here is reproducible with `./scripts/setup-references.sh`.

## Pins

| Project | Checkout | Commit | Version |
|---|---|---|---|
| [obra/superpowers](https://github.com/obra/superpowers) | `references/superpowers` | `2ce8aa15` | v7.0.1 (2026-10-21) |
| [morluto/rea](https://github.com/morluto/rea) | `references/rea` | `26b033d5` | rea-agents 6.8.0 (2026-11-03) |
| [storytold/craft-anything](https://github.com/storytold/craft-anything) | `references/craft-anything` | `2e0d0813` | v0.3.0 (2026-11-03) |

`references/` is gitignored, so these are working copies pinned for reading and
driving the CLIs — not vendored source. Do not edit them.

## Skills

15 Superpowers skills plus `reverse-engineer-anything` are vendored into
`.agents/skills/<name>/SKILL.md`, committed as plain text. Updating means
re-copying from `references/superpowers/skills/` and
`references/rea/.agents/skills/reverse-engineer-anything/`.

`AGENTS.md` is the loader. If the client ever gains a project-skill path
setting, point it at `.agents/skills` for native autoloading.

`rea doctor` reports `skill:identity` drift because the skill was copied rather
than installed by `rea setup`. That is expected and harmless; `rea mcp doctor`
is the check that matters for tool availability.

## Verified working

Evidence from this workspace, not claims from the READMEs:

| Capability | Evidence |
|---|---|
| REA MCP server | `rea mcp doctor` → 229/229 tools, 6/6 prompts, protocol `2025-11-25`, version and catalog digest match |
| Craft MCP server | `doctor` self-test → MCP server answered, protocol `2025-06-18`, 29 tools |
| Craft browser session | `web-site-open --url https://example.com` → `HeadlessChrome/156.0.8078.4`, title "Example Domain" |
| Browser binary | `chromium --version` → Google Chrome for Testing 156.0.8078.4 |
| Both servers handshake | `node scripts/check-mcp.mjs` |

## Browser

Playwright's Chromium is installed at `~/.cache/ms-playwright`. On this Linux
image it could not start initially: `libnspr4`, `libnss3`, then the whole
GTK/ATK/X11/ALSA stack were absent, and the sandbox forbids root, so
`playwright install-deps` cannot run.

`scripts/setup-references.sh` handles that without root: it downloads the 14
required `.deb` files through a user-owned apt state into
`~/.local/lib/chromium-deps`, then writes `~/.local/bin/chromium`, a wrapper
that exports `LD_LIBRARY_PATH` and execs Playwright's headless shell. Craft
Anything detects that wrapper and drives it over CDP.

Consequences worth knowing:

- Playwright used directly still needs
  `LD_LIBRARY_PATH="$HOME/.local/lib/chromium-deps/usr/lib/x86_64-linux-gnu"`.
- With root, prefer `sudo npx playwright install-deps chromium` and delete the
  wrapper — it is a workaround for an unprivileged container, not a design.
- macOS and Windows need none of this; their setup installs the normal browser
  and the script skips the wrapper when a system Chrome is present.

## MCP registration

`.mcp.json` declares both servers at project scope. Claude Code and compatible
clients read it after you approve the folder's servers.

```json
{
  "mcpServers": {
    "rea": { "command": "npx", "args": ["-y", "rea-agents@6.8.0", "mcp"] },
    "craft-anything": { "command": "craft-anything-cli", "args": ["mcp"] }
  }
}
```

The `rea` entry was written by `rea mcp add --agent claude-code --no-global`, so
it is the upstream-supported shape. Verify without a client:

```bash
node scripts/check-mcp.mjs     # handshakes each server, prints tool counts
rea mcp doctor                 # deeper REA check: tools, prompts, digest
```

Other clients: `rea mcp add --agent cursor` (and `rea mcp add --help` for the
list), `craft-anything-cli setup`. Both commands edit client configuration and
are safe to re-run. `craft-anything-cli mcp` is also usable straight from any
MCP client that takes a command and args — the path must be on `PATH`.

Craft gates tools that run code or touch a device. On the command line that is
`--allow-run`; over MCP the client asks. Nothing here bypasses that.

## Native engines and Rust: not needed

`rea doctor` lists Hopper, Ghidra, IDA, JADX and Kuna as missing; craft's doctor
lists Ghidra, adb, JADX, Apktool, Frida, GDB, LLDB, mitmdump, Binwalk, Unblob,
ILSpy, Java, tshark, rizin, rtl433 and Vineflower. All are optional, and none is
needed for this project: every reference target is a web interface, which uses
the JavaScript/browser paths. `objdump` is present for portable binary metadata.

If a native or mobile target ever appears:

- REA: `rea setup` can install Hopper; Ghidra needs `GHIDRA_INSTALL_DIR` pointing
  at an extracted 12.1.x release; IDA, JADX and Kuna are caller-supplied
  (`REA_IDA_MCP_CONFIG`, `REA_JADX_MCP_JAR`, `REA_KUNA_COMMAND`) and REA will not
  download them.
- Craft: Ghidra enables Deep mode; the rest are ordinary system installs.

Rust is not required either. Craft ships prebuilt Linux (x86_64, aarch64),
macOS universal and Windows binaries; building from source needs Rust 1.97+ and
buys nothing here.

## Local setup

Development runs on your machine, so this is the path that matters.

Prerequisites: git, Node `^22.23.4 || ^24.22.1 || >=26.12.1` (REA's range), a
Chrome-family browser, plus `curl`/`tar`/`unzip`.

```bash
git clone git@github.com:donovinsims/milk.git && cd milk
./scripts/setup-references.sh     # pins, both CLIs, browser
node scripts/check-mcp.mjs        # both MCP servers answer
```

Platform notes:

- **macOS** — gets the standalone `craft-anything-cli-0.3.0-macos-universal.zip`;
  Linux has no CLI-only asset, so its binary is taken from the app tarball.
- **Windows** — use WSL. The portable Windows zips are the GUI app, not the CLI.
- The npm install targets the writable prefix automatically (`$HOME/.local`
  when the system prefix is read-only, as with nvm or Homebrew).

## Environment

2 vCPU, 3.8 GB RAM, ~9 GB free. Node 26.13.0, npm 11.20.0, Bun 1.4.4,
Python 3.12.3. No Rust, no root (apt is used through a user-owned state dir).

Binaries live under `/workspace/homes/<id>/.local`. Files survive an archive,
but package trees and caches may be pruned on restore — if `rea`,
`craft-anything-cli` or `chromium` disappears, re-run
`./scripts/setup-references.sh`.
