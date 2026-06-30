# FIX_U61 - Making the stack work with a USB U61 dongle

## Purpose

This document describes the changes made to **lon-stack-dx** so that its
**userspace MIP** link layer can actually drive an **EnOcean/Echelon U61 USB
network interface** (FT232B-based "Echelon USB Network Interface", idVendor
`0x0920`, idProduct `0x7500`) on Linux, without the kernel `u61.ko` line
discipline.

Before these changes the stack opened the serial device but **never
communicated** with the U61: the downlink start-up handshake timed out
(`DOWNLINK_WAIT_STARTUP_RESET → WAIT_STARTUP_RESYNC_ACK` forever), the dongle
sent nothing back (`UPLINK_IDLE`), and no frame was ever transmitted on the
wire. The U61 branch of the userspace MIP was an **unfinished port** (the file
carries ~25 `TODO` markers and contains no U61-specific transmit logic every
`lon_usb_iface_type` test only handled `LON_USB_INTERFACE_U50`).

## Why we backported the driver logic

The kernel driver in **lon-driver** (`u61/U61Link.c`, `lonifd/lonifd.c`) is the
complete, working reference implementation of the U61 host protocol (UMIP). It
is purpose-built for these dongles and has **0** `TODO` markers. The stack's own
`TODO` comments even point to it ("*see the U61 code*").

Rather than reinvent the protocol, we **backported the U61 behaviour from the
driver** into the stack's userspace MIP:

- the U61 **baud rate** (`BRATE_U61a = B460800`, from `lonifd.c`);
- the **active start-up**: the driver sends the *set layer mode* command
  (`{niLMODE, 1, 1}` = `MsgModeL2`) proactively on open (`U61Link.c`,
  `U61LinkWrite(state, MsgModeL2)`);
- the **UMIP frame format**: `FRAME_SYNC` (`0x7E`) + a `0x00` byte, then
  `[length][NiCmd][data…]`, **no trailing checksum** (`U61Link.c`,
  `m_DlPacket[0]=UMIP_ESC; m_DlPacket[1]=0; …`);
- the **length convention**: the on-wire length includes the `NiCmd` byte, so
  the PDU length is `length − 1` (`U61Link.c`, `m_UplinkLength--`).

## How the U61 link now starts up

1. Open `/dev/ttyUSBx` at **460800 8N1**, raw, DTR/RTS asserted.
2. Downlink reaches `DOWNLINK_WAIT_STARTUP_RESET`; on its timeout it calls
   `SendResync()`, which for the **U61** sends the **layer-mode command**
   (`MsgModeL2`) as `7E 00 02 E5 01`.
3. The dongle enters layer-2 mode and **echoes** the layer mode
   (`7E 00 02 E5 01`).
4. `CheckUplinkCompleted()` parses the echo and, for the U61, marks the link
   **ready** (`state->ready = true`, downlink → `DOWNLINK_IDLE`). The U61 has no
   U50-style resync / null / reset handshake.
5. Queued application messages (e.g. a network-management `Query ID`) are now
   transmitted, and incoming layer-2 frames are delivered to the LCS network
   layer.

## Modifications

All changes are guarded by `state->lon_usb_iface_type == LON_USB_INTERFACE_U61`
(or the `USB_MIP` link selection) and leave the U50/U60 behaviour unchanged.

| File | Function | Change | Reason |
|------|----------|--------|--------|
| `abstraction/IzotHal.c` | `HalOpenUsb` | Added the `LON_USB_BAUDRATE` macro (default `B115200`) and used it for `cfsetispeed`/`cfsetospeed` instead of a hard-coded `B115200`. | The U61 runs at **460800** baud; `115200` only suits the U50. Override with `-DLON_USB_BAUDRATE=B460800`. |
| `lon_usb/lon_usb_link.c` | `SendResync` | Added a U61 branch that sends the layer-mode command (`MsgModeL2`/`MsgModeL5`) instead of being a no-op. | The U61 has no resync command; it must be **prompted** with the layer mode to start talking (driver behaviour). |
| `lon_usb/lon_usb_link.c` | `WriteDownlinkMessage` | For the U61, emit a sync-only header (`FRAME_SYNC` + `0x00`) instead of the U50 code packet, and **omit the trailing checksum**. | The U61 UMIP frame is `7E 00 [length][NiCmd][data]` with no command/sequence/ACK and no checksum. |
| `lon_usb/lon_usb_link.c` | `ProcessUplinkBytes` / `CheckUplinkCompleted` | U61 message completion uses `index > length` (vs `index > length + 1` for the U50). | The U61 length field counts the `NiCmd` byte; the U50 length counts only PDU bytes. |
| `lon_usb/lon_usb_link.c` | `CheckUplinkCompleted` | On the layer-mode echo, mark the link ready for the U61 (`ready = true`, downlink → `DOWNLINK_IDLE`). | Completes the U61 start-up, which has no U50 resync/null/reset sequence. |
| `lcs/lcs_link.c` | `LinkLayerUsbReceive` | For `LINK_IS(USB_MIP)`, initialise `lpduSize`/`lpduHeaderPtr` from the received message and forward only `LonNiIncomingL2Cmd` frames. | These were only set in the `MULTIPLE_USB_MIPS`/power-line branch; for a single USB MIP they were **uninitialised**, causing a segfault on the first received packet. |

### Note on the PDU length

`ReadLonUsbMsg()` already converts the wire length to a PDU-only length
(`out_msg->short_pdu_length = … − 1`). The completion change above only fixes
*when* the frame is considered complete; it must **not** also adjust the length,
otherwise the last PDU byte is dropped (a double `−1`).

## Building for the U61

The stack uses a hard-coded `115200`/U50 default for backward compatibility, so
the U61 settings must be supplied at configure time:

```
-DLON_USB_IFACE_TYPE=LON_USB_INTERFACE_U61
-DUSB_DEV_NAME=/dev/ttyUSB0
-DUSB_LINE_DISCIPLINE=-1          # userspace MIP, no kernel line discipline
-DLON_USB_BAUDRATE=B460800        # U61 baud
```

The `lon_var` tool drives this automatically (`LONVAR_STACK_BAUD=B460800`,
forwarded as `target_compile_definitions(lon_stack_dx PRIVATE
LON_USB_BAUDRATE=…)`).

## Reference

- `lon-driver/u61/U61Link.c` : UMIP framing, `MsgModeL2`, length convention.
- `lon-driver/lonifd/lonifd.c` : `BRATE_U61a = B460800`, line-discipline setup.
