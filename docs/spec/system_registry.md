# System Registry

Catalog of ODE systems included in the dataset.

## v1_core

- `vanderpol_unforced`
  - family: `v1_core`
  - state dimension: `2`
  - parameters: `mu`
  - vector field: `x1_dot = x2`, `x2_dot = mu * (1 - x1^2) * x2 - x1`
  - current variants:
    - `smoke_mu1_full_state`
    - `formal_mu1_to_3_full_state`
