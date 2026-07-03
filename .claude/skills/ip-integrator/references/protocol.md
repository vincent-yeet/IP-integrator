# Protocol Conventions

Used when an IP declares `interface_protocol: <name>` instead of (or alongside) a pasted
module header. When a recognized protocol is named, expand a `connections` entry between two
matching interfaces into the full per-channel wiring below — don't leave it as one opaque link.

Signal names here are the common convention; always prefer the actual names in a pasted
`interface` header or `path` RTL over these defaults if they differ (e.g. a project prefixing
everything `m_axi_*`). These conventions tell you *what exists and how it behaves*, not what
it must literally be called.

## AXI4

Full protocol, 5 independent channels, each with its own valid/ready handshake. Treat each
channel as its own `type: backpressure` connection when expanding — do not merge them.

| Channel | Direction (master→slave) | Key signals | Notes |
|---|---|---|---|
| Write Address (AW) | master→slave | `awaddr, awlen, awsize, awburst, awid, awvalid/awready` | `awlen`+`awsize`+`awburst` define the burst — treat as `type: burst` |
| Write Data (W) | master→slave | `wdata, wstrb, wlast, wvalid/wready` | `wlast` marks final beat of the burst |
| Write Response (B) | slave→master | `bresp, bid, bvalid/bready` | one response per burst, not per beat |
| Read Address (AR) | master→slave | `araddr, arlen, arsize, arburst, arid, arvalid/arready` | mirrors AW |
| Read Data (R) | slave→master | `rdata, rresp, rlast, rid, rvalid/rready` | `rlast` marks final beat |

**Non-trivial parts that generated glue must not gloss over:** `arid`/`awid`/`bid`/`rid` allow
outstanding, out-of-order transactions — if the target IPs actually use IDs (not tied to 0), a
generated adapter needs to preserve ID matching between request and response, not just pass
data through. If in doubt, ask whether the design actually needs multiple outstanding
transactions, or whether IDs can be tied off — the latter is far simpler to generate correctly.

## AXI4-Lite

Same 5 channels as AXI4, but no burst support and no IDs — every transaction is a single beat.
`awlen`/`arlen`/`wlast`/`rlast`/`*id` don't exist. Treat every channel connection as plain
`type: backpressure`, never `burst`. This is the right default for simple register/control
interfaces where full AXI4 would be overkill — flag to the user if a spec asks for `axi4` on
something that's clearly just register access, since `axi4_lite` is usually the better fit.

## SPI

Not a valid/ready handshake — clock-edge-driven serial framing. Master generates `sclk`; data
shifts on each clock edge (CPOL/CPHA determine which edge).

| Signal | Direction (master→slave) | Notes |
|---|---|---|
| `sclk` | master→slave | Serial clock, master-generated — this is a *derived* clock domain, treat any logic sampling on it as needing the same CDC scrutiny as a separate clock |
| `mosi` | master→slave | Master-out-slave-in data |
| `miso` | slave→master | Master-in-slave-out data |
| `cs_n` | master→slave | Chip select, active-low by convention; one per slave if multiple slaves share `sclk`/`mosi`/`miso` |

**Ask, don't assume:** CPOL/CPHA mode (0/1/2/3) and bit order (MSB-first vs LSB-first) are not
inferrable from a generic "SPI" label — these must come from the spec or the IP's own
documentation, since a wrong guess produces logic that looks structurally fine but reads
garbage data.

## I2C

Two-wire, open-drain, multi-master-capable. Fundamentally different electrically from the
above (open-drain requires pull-ups, not push-pull drivers) — flag this if generating a
top-level that needs an actual pad/IO cell, since plain internal logic connections don't
capture the open-drain requirement.

| Signal | Notes |
|---|---|
| `scl` | Serial clock, open-drain |
| `sda` | Serial data, open-drain, bidirectional |

Addressing (7-bit vs 10-bit) and clock stretching support must come from the spec — don't
assume 7-bit as a silent default without flagging it.

## Wishbone

Simple synchronous handshake, single clock domain by convention (no separate CDC concerns
unless the spec explicitly puts masters/slaves in different domains).

| Signal | Direction (master→slave) | Notes |
|---|---|---|
| `adr` | master→slave | Address |
| `dat_o` / `dat_i` | both directions | Naming is from the master's perspective: `dat_o` is master's output |
| `we` | master→slave | Write enable |
| `stb` | master→slave | Strobe — "this is a valid cycle" |
| `ack` | slave→master | Acknowledge — completes the cycle |
| `cyc` | master→slave | Bus cycle in progress |

Treat `stb`/`ack` as the `type: backpressure` handshake pair; `cyc` frames the overall
transaction and should stay asserted for its duration.

## Adding a new protocol

Same shape each time: list the channels (if more than one), the signals per channel with
direction, which signals form the valid/ready-equivalent handshake pair, and anything
electrically unusual (open-drain, derived clocks) that plain internal wiring wouldn't capture
correctly. Add it here rather than letting Claude reconstruct it from memory each time it comes
up — that's the whole point of pulling this into a reference file.