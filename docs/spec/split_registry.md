# Split Registry

Catalog of dataset split definitions.

## v1_core Van der Pol

- `vanderpol_smoke_split_i`
  - type: `initial_condition`
  - grouping unit: `trajectory`
  - ratios: `0.75 / 0.125 / 0.125`

- `vanderpol_formal_split_i`
  - type: `initial_condition`
  - grouping unit: `trajectory`
  - ratios: `0.70 / 0.15 / 0.15`

- `vanderpol_formal_split_p`
  - type: `parameter`
  - parameter: `mu`
  - grouping unit: `trajectory`
  - ratios: `0.70 / 0.15 / 0.15`
  - policy: sort trajectories by `mu`, then assign disjoint train, validation, and test parameter blocks.
