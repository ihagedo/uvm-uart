# `rtl/`: the design under test

A full-duplex UART from [CHIPKIT](https://github.com/whatmough/CHIPKIT) (P. Whatmough et al., Harvard VLSI-Arch group), copied at commit `11c76bb`. CHIPKIT is MIT-licensed (see its README).

| File | Upstream path | Local change |
|---|---|---|
| `uart.sv` | `ip/commctrl/uart.sv` | none |
| `comm_defs_pkg.sv` | `ip/commctrl/comm_defs_pkg.sv` | none |
| `rtl_macros.svh` | `ip/rtl_inc/RTL.svh` | renamed to the name `uart.sv` includes; removed a stray `*/` in the `` `LOG `` macro that VCS rejects |

## What the testbench needs to know

- `baud_div` sets the bit period: one bit is 4 × `baud_div` clocks. `top_tb` ties it to 217, so at 100 MHz a bit is 8680 ns (115 207 baud).
- Frames are 1 start bit, 8 data bits (LSB first) and no parity. The transmitter sends 2 stop bits. The receiver checks 1 stop bit and pulses `rx_done` in the middle of it.
- The receiver detects the start bit on a quarter-bit tick, so `rx_done` can land up to a quarter bit early or late.
- `top_tb` loops the receiver back into the transmitter (`txen = rx_done`, `tx_byte = rx_byte`). The transmitter ignores `txen` while it is still sending, and there is no FIFO.
