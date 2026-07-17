# Elytra XYZ Simulator (`;e`)

[Back to the main README](README.md)

Start a command with `;e` to keep the complete position and velocity state: `x`, `y`, `z`, `vx`, `vy`, and `vz`.

The `;e` simulator defaults to `inertia(0.003)` and `sdel(0)` for modern Minecraft movement.

| Command | What it does |
| --- | --- |
| `e([ticks = 1, pitch, yaw])` | Simulate Elytra ticks, optionally setting pitch and yaw. |
| `ej(floor_y[, pitch, yaw])` | Land and jump during the stale Elytra transition tick. Alias: `ejump`. |
| `esj(floor_y[, pitch, yaw])` | Simulate the landing jump with the sprint-jump horizontal boost. |
| `el(floor_y[, pitch, yaw])` | Set the landing height and vertical velocity to zero, then simulate one Elytra tick. Alias: `eland`. |
| `pitch(n)` / `p(n)` | Set the stored pitch. |
| `outp([target])` | Output the stored pitch, optionally relative to a target. |
| `pitchqueue(...)` / `pq(...)` | Queue pitch values like `aq(...)` queues yaw values, applies to non-elytra ticks too. |


Existing movement functions also work in `;e`. Ground ticks use XZ movement, while jump and air ticks combine the existing XZ and Y simulators into one tick.
