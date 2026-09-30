# Matrix Accelerator

## 4×4 Hardware Matrix Multiplication Accelerator — RTL to GDSII

A complete digital VLSI implementation of a **4×4 unsigned matrix multiplication accelerator**, designed at RTL and taken through the **RTL-to-GDSII flow** using **Cadence digital implementation tools**, with **Siemens Tessent** used for Design-for-Test (DFT).

The project focuses on implementing a compact accelerator through the complete ASIC design flow while exploring the trade-off between **hardware resource sharing, area, performance, latency, and testability**.

---

## Project Overview

The accelerator computes the matrix multiplication:

$$
C = A \times B
$$

for two 4×4 unsigned matrices.

Each output element is calculated as:

$$
C[i][j] = \sum_{k=0}^{3} A[i][k] \times B[k][j]
$$

Instead of using a separate multiplier for every multiplication, the design uses **one shared 4×4 multiplier** and reuses it sequentially across all matrix elements.

This reduces duplicated multiplier hardware while increasing the number of cycles required to complete the operation.

---

## Key Design Features

* **4×4 matrix multiplication**
* **4-bit unsigned operands**
* **Single shared 4×4 multiplier**
* **10-bit accumulation datapath**
* **8-bit result storage**
* Sequential **MAC-based computation**
* Dedicated control **FSM**
* Input storage for matrices A and B
* Output storage for matrix C
* Saturating 8-bit output
* Single clock domain
* Synthesizable Verilog RTL
* Functional RTL verification
* Complete RTL-to-GDSII implementation
* Scan insertion and DFT
* EDT implementation
* ATPG
* Physical design and routing
* Final GDSII generation

---

# Architecture

The accelerator consists of three major parts:

```text
                 +----------------+
                 |    A Memory    |
                 |    16 × 4      |
                 +-------+--------+
                         |
                         |
                         v
                   +-----------+
                   |           |
                   |  Shared   |
                   |  4×4      |
                   | Multiplier|
                   |           |
                   +-----+-----+
                         |
                         v
                   +-----------+
                   |  10-bit   |
                   | Accumulator|
                   +-----+-----+
                         |
                         v
                 +----------------+
                 |    C Memory    |
                 |    16 × 8      |
                 +-------+--------+
                         |
                         v
                    Output Data


                 +----------------+
                 |    B Memory    |
                 |    16 × 4      |
                 +-------+--------+
                         |
                         +-------> Shared Multiplier
```

The multiplier is deliberately shared instead of replicating multiplier hardware for every matrix operation.

This makes the architecture more **area-conscious**, while computation is performed sequentially.

---

# Datapath

### Operand Width

Each matrix element is:

```text
4-bit unsigned
```

Therefore:

```text
0 to 15
```

The maximum multiplication is:

```text
15 × 15 = 225
```

which requires 8 bits.

### Accumulator Width

Each output element contains four multiplication terms:

```text
4 × (15 × 15)
= 4 × 225
= 900
```

Therefore a **10-bit accumulator** is used:

```text
900 < 1024 = 2^10
```

The accumulator is reused for every output element.

---

# Storage Architecture

The design uses register-based storage for the matrices.

### Matrix A

```text
16 entries × 4 bits
= 64 bits
```

### Matrix B

```text
16 entries × 4 bits
= 64 bits
```

### Matrix C

```text
16 entries × 8 bits
= 128 bits
```

### Total Matrix Storage

```text
64 + 64 + 128 = 256 bits
```

These RTL memories are implemented as register storage rather than an external SRAM macro.

---

# Computation Strategy

The accelerator calculates each output element using a sequential MAC operation.

For example:

```text
C[0][0] =
A[0][0] × B[0][0] +
A[0][1] × B[1][0] +
A[0][2] × B[2][0] +
A[0][3] × B[3][0]
```

The same multiplier and accumulator are reused for every output.

For each output element:

```text
1 cycle  → Accumulator initialization
4 cycles → Multiply and accumulate
1 cycle  → Write result
```

Therefore:

```text
6 cycles / output
```

and for all 16 output elements:

```text
16 × 6 = 96 computation cycles
```

This is a deliberate **resource-sharing architecture** rather than a fully parallel implementation.

---

# Control FSM

The accelerator is controlled using a finite-state machine.

The main states are:

```text
        +--------+
        |  LOAD  |
        +----+---+
             |
             v
        +--------+
        | READY  |
        +----+---+
             |
             v
        +--------+
        |  INIT  |
        +----+---+
             |
             v
        +--------+
        |  MAC   |
        +----+---+
             |
             v
        +--------+
        |  WRITE |
        +----+---+
             |
             +------> Next output
             |
             v
        +--------+
        |  DONE  |
        +--------+
```

The FSM controls:

* Matrix loading
* Output-element selection
* MAC sequencing
* Accumulator control
* Result writeback
* Completion indication
* Result readout

---

# RTL Design

The accelerator was designed in **Verilog RTL**.

The RTL includes:

* Matrix A storage
* Matrix B storage
* Matrix C storage
* Shared multiplier datapath
* Accumulator
* Control FSM
* Input loading interface
* Output readout interface
* Start / ready / done control

The main RTL design is available in:

```text
rtl/
```

---

# Functional Verification

A dedicated Verilog testbench was created to verify the RTL functionality before physical implementation.

The functional verification flow covered the matrix multiplication operation and the control sequence of the accelerator.

RTL simulation was completed before proceeding through the implementation flow.

---

# ASIC Implementation Flow

The design was taken through a complete digital ASIC implementation flow.

```text
                 RTL DESIGN
                     |
                     v
              FUNCTIONAL SIM
                     |
                     v
                SYNTHESIS
                     |
                     v
             DFT / SCAN INSERTION
                     |
                     v
                   EDT
                     |
                     v
                  ATPG
                     |
                     v
                FLOORPLAN
                     |
                     v
                 PLACEMENT
                     |
                     v
                   CTS
                     |
                     v
                 ROUTING
                     |
                     v
                   STA
                     |
                     v
                  GDSII
```

---

# Tools Used

## Cadence EDA

The RTL-to-GDSII implementation flow was carried out using **Cadence EDA tools**.

Cadence was used for the digital implementation stages including:

* RTL synthesis
* Design optimization
* Floorplanning
* Placement
* Clock Tree Synthesis (CTS)
* Routing
* Timing analysis
* Physical implementation
* GDSII generation

The design was taken from RTL through physical implementation and finally exported as a **GDSII layout**.

---

## Siemens Tessent

**Siemens Tessent** was used for the Design-for-Test portion of the project.

The DFT flow included:

* Scan insertion
* Scan architecture
* EDT
* ATPG

Tessent was used to prepare the design for manufacturing-test-oriented analysis and test generation.

---

# Design-for-Test (DFT)

DFT was incorporated into the design as part of the ASIC implementation flow.

The DFT flow included:

```text
Design
   |
   v
Scan Insertion
   |
   v
EDT
   |
   v
ATPG
```

The project therefore covers both the **functional design flow** and the **testability/DFT flow**.

---

# Physical Design

After synthesis and DFT processing, the design was taken through physical implementation.

The physical-design stages included:

### Floorplanning

The design was prepared for physical implementation and organized within the target technology environment.

### Placement

Standard cells were placed within the floorplan.

### Clock Tree Synthesis

A clock distribution network was implemented to distribute the clock through the design.

### Routing

Signal and clock connections were routed to complete the physical implementation.

### Static Timing Analysis

Timing analysis was performed as part of the implementation flow.

### GDSII

The final physical design was exported as a **GDSII layout**.

The final GDSII and relevant physical-design artifacts are maintained under:

```text
physical_design/
```

---

# Technology

The design was implemented using a **generic PDK / technology environment provided with the Cadence design environment**.

The project therefore demonstrates the complete digital implementation methodology without tying the design to a specific commercial or open-source foundry technology.

---

# Repository Structure

```text
matrix-accelerator/
│
├── README.md
│
├── rtl/
│   ├── matmul4x4_accel.v
│   └── tb_matmul4x4_accel.v
│
├── dft/
│   ├── scan/
│   ├── edt/
│   └── atpg/
│
├── synthesis/
│
├── physical_design/
│
├── reports/
│
└── docs/
```

### `rtl/`

Contains the original Verilog RTL and functional verification testbench.

### `dft/`

Contains retained DFT-related implementation artifacts.

### `synthesis/`

Contains retained synthesis-related artifacts.

### `physical_design/`

Contains final physical implementation files including the GDSII.

### `reports/`

Contains retained implementation reports.

### `docs/`

Contains project documentation, architecture images, implementation-flow screenshots, and final layout images.

---

# Project Highlights

### Hardware Resource Sharing

Rather than implementing many multiplier units, the design uses:

```text
1 × shared 4-bit multiplier
1 × shared 10-bit accumulator
```

The hardware is reused across the complete matrix multiplication.

---

### Compact Datapath

The design deliberately uses small operand widths:

```text
A → 4-bit
B → 4-bit
Product → 8-bit
Accumulator → 10-bit
C → 8-bit
```

This keeps the datapath compact while maintaining the required numerical range.

---

### Complete ASIC Flow

The project goes beyond RTL design and simulation.

It covers:

```text
RTL
→ Synthesis
→ DFT
→ Scan
→ EDT
→ ATPG
→ Floorplan
→ Placement
→ CTS
→ Routing
→ STA
→ GDSII
```

---

### From Architecture to Physical Layout

The project demonstrates the progression from a hardware architecture and Verilog RTL to an implemented physical layout.

The `docs/` directory contains selected images showing the design architecture, implementation flow, and final physical layout.

---

# Future Improvements

Possible future extensions include:

* Larger matrix dimensions
* Wider operands
* Multiple processing elements
* Parallel multiplier architectures
* Pipelined matrix multiplication
* SRAM-based matrix storage
* Improved throughput
* Power optimization
* Area/performance exploration
* More advanced accelerator architectures

---

# Project Goal

The primary goal of this project was to gain practical experience with the **complete ASIC development flow**, starting from a hardware architecture and Verilog RTL and progressing through:

```text
Design
   ↓
Verification
   ↓
Synthesis
   ↓
DFT
   ↓
Physical Design
   ↓
Timing Analysis
   ↓
GDSII
```

The project demonstrates how architectural decisions such as **resource sharing and operand width** influence the resulting hardware implementation and how an RTL design ultimately becomes a physical silicon layout.

---

## Author

**Mohammed Arbaz Ali**

Digital VLSI / ASIC Design Project

**Technologies:** Verilog • Cadence EDA • Siemens Tessent • DFT • ATPG • Physical Design • GDSII
