# ODEs_dataset

The main entry point of this repository is `docs/`, not `README`.

For human readers, `docs/` is usually the only directory that needs to be read. It already contains the project goals, engineering structure, specifications, task records, and explanation documents. This `README` is intentionally minimal.

## Recommended Use

This repository is intended to be handled directly by a coding AGENT such as Codex or Claude Code rather than by manually reading source files from the top down.

For an AGENT, the recommended reading order is:

1. `docs/project guide/`
2. `docs/spec/`
3. `docs/notes/code explanation/`
4. `docs/notes/file explanation/`
5. `docs/notes/mathematical explanation/`

This order means:

- `project guide` defines the project goals, engineering roadmap, and top-level constraints.
- `spec` records the current project registry, object registry, and task list.
- The three `explanation` folders together contain the project instructions, generated-file explanations, and mathematical background.

## Julia And Dependencies

This project uses the Julia language.

Package installation, environment setup, and other dependency handling may be delegated to the AI agent. The agent should install or instantiate whatever is required for the task instead of expecting a human to prepare the environment manually.

## Minimal Note For Human Readers

If you want to understand the project, start from `docs/` and not from the source tree.

If you want an AGENT to work on this repository, giving it the reading order above is usually enough. A separate manual explanation of the repository layout is usually unnecessary.

## Repository Role

`ODEs_dataset` is an ODE test dataset engineering repository. Its full documentation is maintained in `docs/` and is not repeated here.
