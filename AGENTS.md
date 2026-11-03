# milk

UI reference library for the product we're about to build. `attio/` and `dench/`
hold verified screenshots of two competing CRM-style workspaces, catalogued in
[INDEX.md](INDEX.md). There is no application code yet — the stack gets chosen in
the first design doc, not assumed here.

## Working method: the skills in `.agents/skills` are mandatory

This repo vendors [Superpowers](https://github.com/obra/superpowers) v7.0.1
(15 skills) plus REA's `reverse-engineer-anything` skill. They are process, not
suggestions.

1. Start every session by reading `.agents/skills/using-superpowers/SKILL.md`.
2. Before any other action — including clarifying questions and exploring the
   repo — check the index below and read every skill that applies.
3. Announce "Using <skill> to <purpose>", then follow the skill exactly,
   including the files in its own directory.

Scale the process to the request: a factual question, a one-line fix or a copy
change does not need a design doc. Anything that builds a feature, changes
behaviour, or fixes a bug goes through its skill.

| Skill | Read it when |
|---|---|
| `using-superpowers` | Always, first, every session |
| `brainstorming` | Before any creative work: features, components, behaviour, plans |
| `writing-plans` | Once a spec exists, before touching code |
| `executing-plans` | Running a plan inline, in this session |
| `subagent-driven-development` | Running a plan through per-task subagents with review |
| `dispatching-parallel-agents` | 2+ independent tasks with no shared state |
| `test-driven-development` | Before writing any implementation code |
| `systematic-debugging` | On any bug, failing test or surprising behaviour, before fixes |
| `verification-before-completion` | Before claiming anything is done, fixed or passing |
| `requesting-code-review` | After implementing, before merging |
| `receiving-code-review` | When review feedback arrives |
| `finishing-a-development-branch` | Implementation complete, tests green, integration undecided |
| `using-git-worktrees` | Isolating feature work from the current checkout |
| `writing-skills` | Creating or editing a skill |
| `diagnosing-superpowers` | A session ran badly and the cause needs evidence |
| `reverse-engineer-anything` | Studying a shipped artifact (site, Electron/JS app, binary, APK) with REA |

### Process order for features

`brainstorming` → `writing-plans` → `executing-plans` or
`subagent-driven-development` → `test-driven-development` →
`requesting-code-review` → `receiving-code-review` →
`verification-before-completion` → `finishing-a-development-branch`.

Do not skip a step silently. If one genuinely does not apply, say so and why.

### Harness notes: this is Freebuff, not Claude Code

Superpowers is written against Claude Code tool names. Translate:

| The skill says | Do this here |
|---|---|
| Use the Skill tool / `superpowers:<name>` | `read_files` `.agents/skills/<name>/SKILL.md` |
| Dispatch a subagent (`Task`) | `spawn_agents` |
| TodoWrite | The session task list — one item per checklist entry |
| Enter plan mode | No plan mode exists: write the design/plan file and get approval in chat |
| Create a worktree | Already isolated — this chat owns a worktree on `freebuff/<chat-id>`; never nest another |
| Open the visual companion | Start a dev server on `0.0.0.0` and call `cloud_show_dev_server`; read `brainstorming/visual-companion.md` first |
| SessionStart hooks, plugins, `/plugin` | Absent — this file is the bootstrap |

## External tooling

Two upstream projects are wired in for studying interfaces and shipped
artifacts; setup and caveats are in [docs/tooling.md](docs/tooling.md).

- **REA** (`rea`, rea-agents 6.8.0) — evidence-backed reverse engineering of
  websites, Electron/JS apps, native binaries, .NET, APKs and more.
- **Craft Anything** (`craft-anything-cli` 0.3.0) — 314-tool engine whose
  `web_site_capture` / `web_page_screenshot_take` give measured layout, design
  tokens and widths of a live site, and whose likeness checks compare a rebuild
  against the original.

Prefer these over guessing how a reference product works. Both are installed
and verified here, browser included; native-analysis engines are deliberately
absent and are not needed for web targets. See [docs/tooling.md](docs/tooling.md)
for what is verified and what each tool needs.

## references/

`references/` holds pinned third-party checkouts (superpowers, rea,
craft-anything). It is gitignored: read those trees, never edit them. Restore or
reinstall everything with `./scripts/setup-references.sh`.

## Conventions

- Design docs go to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, plans
  to `docs/superpowers/plans/`, both committed.
- Add no framework, dependency or scaffold before a design doc picks it.
- Stack, product name and scope are all still open — ask rather than infer.
