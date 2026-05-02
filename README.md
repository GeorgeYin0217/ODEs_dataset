# ODEs_dataset

`ODEs_dataset` is a Julia engineering repository for building reproducible ODE benchmark datasets. It is intended to act as a protocol library, data factory, and evaluation base for dynamical-system learning tasks, not just as a folder of saved trajectory files.

The project standardizes the path from an ODE system and initial conditions to generated state trajectories, observed data, train/validation/test splits, benchmark windows, task objects, manifests, diagnostics, and reports. The main downstream use cases are short-term prediction, long-horizon rollout, system identification, representation learning, Koopman/operator approximation, spectral diagnostics, parameter or observation generalization, noise robustness, and long-time statistics.

## What Is Included

The repository currently contains:

- reusable Julia source code for ODE dynamics, observation handling, dataset generation, splits, diagnostics, manifests, and reporting;
- declarative configuration files for systems, observations, splits, tasks, and benchmark runs;
- smoke and formal experiment entry points under `experiments/`;
- generated data, manifests, reports, plots, tables, logs, and notebooks organized by task scope;
- project specifications and task records under `docs/spec/`;
- task plans, generated-file explanations, and mathematical notes under `docs/notes/`;
- project guides describing the dataset protocol, object model, engineering roadmap, and intended benchmark structure.

The registered systems include internal sanity systems such as diagonal linear, rotation-contraction, and Jordan/nonnormal linear dynamics, plus benchmark systems such as linear oscillator, Van der Pol, Duffing, Lotka-Volterra, FitzHugh-Nagumo, Lorenz63, Rossler, Lorenz96, nonlinear pendulum, and controlled Duffing for EDMDc-style workflows.

This repository is designed to be read, managed, and operated with the help of an AI coding agent.

The main entry point is `docs/`. That folder already contains the full project logic, including the goals, engineering structure, specifications, task records, and explanation documents. This `README` is only a short guide for how the repository is meant to be used.

## Recommended Use

The preferred way to use this repository is to let a coding agent such as Codex or Claude Code take over the reading, navigation, modification, and execution work.

In practice, a user who wants to understand, use, or modify this project does not need to manually inspect the whole source tree first. It is usually enough to ask the agent to read the documentation in order and then carry out the task.

For an AI agent, the recommended reading order is:

1. `docs/project guide/`
2. `docs/spec/`
3. `docs/notes/code explanation/`
4. `docs/notes/file explanation/`
5. `docs/notes/mathematical explanation/`

If the agent reads these folders in order, it should be able to fully understand how this repository is organized, what it is trying to do, and how the main engineering logic fits together.

The roles of these folders are:

- `project guide` defines the project goals, engineering roadmap, and top-level constraints.
- `spec` records the current project registry, object registry, and task list.
- The three `explanation` folders together contain the project instructions, generated-file explanations, and mathematical background.

## Julia And Dependencies

This project uses the Julia language.

Package installation, environment setup, and other dependency handling may also be delegated to the AI agent. The agent can install, instantiate, or prepare whatever is required for the task instead of relying on a human to do environment preparation first.

## For Human Users

If you want to understand the project yourself, start from `docs/` rather than from the source tree.

If you want to use this repository or change it, you can usually let an AI agent handle the process for you. In most cases, telling the agent to read `docs/` in the order above is enough to get it oriented.

## Repository Role

The full project documentation is maintained in `docs/` and is not repeated here. Treat this README as the minimal orientation page, then use `docs/project guide/` and `docs/spec/` for the authoritative project description and current task registry.
