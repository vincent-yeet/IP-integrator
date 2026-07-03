---
name: IP Integrator
description: This skill is used to integrate existing IPs and write glue logic based on user given high level specifications. Trigger when /integrate is used.
---

# IP Integrator

## Instructions
1. The user provides the path to the YAML spec as an argument. If no path or file was given, ask the user for it.
2. Read the YAML file at the path.
3. Parse the following fields: 'intent', 'ips', 'interconnects', 'external_ports', 'sim' Validate as you go: every `masters`/`slaves`/`spokes`/instance reference inside `interconnects` must resolve to a name declared in `ips`. If it doesn't, stop and flag the mismatch rather than generating for a nonexistent IP.
4. Build a port inventory for each IP. Read the ports from 'interface' (or 'path' if no header is given), take note of direction, width, and   clock/reset domain.
5. For each entry in 'interconnects', note what it requires based on its 'topology':
    - 'point_to_point': a direct link between two named ports
    - 'shared_bus'/'crossbar': an arbiter/decoder sized to `masters`/`slaves`, respecting `arbitration`
    - 'mesh_2d'/'systolic': - `mesh_2d`/`systolic` → a generated for-loop instantiation over `dims`, wired per `neighbor_connections`
    - `tree`/`star`/`daisy_chain`/`broadcast` → structure-specific instantiation per their fields
   Flag anything the spec leaves ambiguous (missing `arbitration`, missing `priority_order`,
   a `flow` that isn't stated) instead of silently defaulting it.
6. For each resolved link, check whether it needs adaptation: width mismatch → converter; different clock domains → synchronizer, never a direct wire across domains; `flow: backpressure` → propagate valid/ready correctly to both winners and non-winners on shared topologies, not just direct links.
7. Generate the glue logic. Default to inlining it in the top-level module. Pull a piece out into its own module if one of these applies:
    - Reused more than once: anything inside a `mesh_2d`/`systolic`/`tree`/`daisy_chain` array's generated loop *must* be a module, since you're instantiating the same logic by index; a single tie-off reused across array elements also qualifies even though it's trivial in isolation.
    - Stateful: CDC synchronizers, async FIFOs, arbiters with a rotating priority register. Worth isolating and naming even when it's a single flop, since state is exactly what's easy to get subtly wrong and worth being able to point to and reason about on its own.
    - Worth testing independently: this is about risk, not size. A short width converter can still hide a bit-order or off-by-one bug worth catching with its own isolated testbench (see step 10) rather than only ever being exercised inside a full top-level simulation.
    A single-use, stateless piece of glue (a tie-off, a mux, a multi-line but purely combinational bit-adaptation) stays inline — wrapping it in its own file adds a port list and an instantiation for something just as readable in place. When something does get its own module, name the file/module descriptively based on what it connects (e.g. `dma_to_mem_width_adapter.sv`, not `glue1.sv`), and comment every port with which IP/signal it connects to on each side.
8. Generate the top level module instantiating every IP, glue module, and the appropriate inline glue logic wired with named port connections. Include 'external_port' at the top level.
9. Self-check before presenting: flag any unconnected port, any width mismatch without a converter, any CDC without a synchronizer, and any arbitration/flow decision that was assumed rather than stated in the spec.
10. If `sim.tool` is given, generate a matching testbench and the run command, matching testbench style to the tool (e.g. Verilator favors a C++/SV harness, Icarus/ModelSim/VCS can use a plain SV testbench or UVM if the project already uses it) and reusing `sim.existing_tb` conventions if provided. Prioritize testing what step 9 flagged — glue modules, CDC crossings, arbitration policies, unstated assumptions — over untouched direct wires. Report pass/fail rather than assuming a clean run; if the simulator isn't actually invokable in the current environment, say so and hand over the testbench and run command instead.
11. Iterate until it passes, or stop and report. If step 10's simulation fails any assertion, treat it as a bug: diagnose against the specific
failure (not a broad rewrite), fix the responsible glue module or top-level wiring, and re-run simulation. Repeat up to 5 times. If it still fails after 5 attempts, stop — present the generated files, the failing testbench, the last failure output, and a clear statement of what's still wrong, rather than silently continuing to iterate or declaring success on an unresolved failure.

## Examples
[Concrete examples of using this Skill]