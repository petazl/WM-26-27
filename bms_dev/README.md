# Moto BMS Monitor — Software Structure

This is the visualisation software for the Warwick Moto custom BMS. It shows the battery pack data live (cell voltages, temperatures, faults) during and after charge cycles, and will log each session so previous charges can be reviewed.

This README explains how the architecture of the software but if you only want to run it, skip to [Running it](#running-it).

> **NOTE:** this software only *monitors* and displays data from the pack. All protection (over-voltage, under-voltage, over-temperature, contactor control) is done by the BMS firmware and hardware. If the laptop crashes or the cable comes out, the pack must still protect itself.

---

## 1. Key Software Design Considerations

| Term | What it actually is |
|---|---|
| **C#** | All the logic is written in this language: reading data, decoding it, checking it, deciding what to show. |
| **.NET** | The platform that runs the C# programs. It runs the compiled code on the laptop, plus a large library of ready-made building blocks (timers, file writing, serial ports and so on) so we don't write those ourselves. REALLY IMPORTANT: we use modern .NET, not the older ".NET Framework". |
| **Windows Forms (WinForms)** | The part of .NET that draws the window: buttons, labels, the coloured cell tiles for voltage status and the SoC status bar. |
| **`.cs` file** | A plain-text file containing C# code. When you press Build, Visual Studio compiles all the `.cs` files together into a single program (`.exe`). Splitting the code into several files is purely for organisation and separating development |

**Why not Python + Tkinter?** This was the original plan (Flask for data handling, Tkinter for the window). C# + .NET was chosen instead because it does the job as one program in one language: no separate web-server layers, and an easy way to produce a ready-to-run app for the team (Python needs an extra bundling tool such as PyInstaller), and a richer set of ready-made window controls. .NET runs on Windows, macOS and Linux, and using the Avalonia UI framework keeps the app cross-platform. The trade-off is that Python’s CAN/DBC libraries (python-can, cantools) are more mature than C#’s equivalents. Those libraries can still be used to reverse-engineer previous dbc files and vcu stuff.

---

## 2. The big picture: how data flows

```
                 BIKE                                          LAPTOP
┌───────────────────────────────────┐
│ Cells → cell monitor IC(CMU) →    │   CAN messages           ┌──────────────────────┐
│ STM32 (BMS firmware)(MCU)         │ ──────────────────►      │ USB-to-CAN adapter   │
└───────────────────────────────────┘   (ID + 8 bytes)         └──────────┬───────────┘
                                                                          │ USB
   ┌──────────────────────────────────────────────────────────────────────┘
   │
   │   One of these "sources" is chosen (all follow the IBmsSource contract):
   │
   ├─► CanBmsSource        real hardware          (planned)  ─┐
   │                                                          ├─► CanBmsDecoder (planned)
   │   SimulatedCanSource  fake raw CAN messages  (planned)  ─┘    decodes + collates
   │                                                                    │
   │   SimulatedBmsSource  fake finished readings (working now) ──┐     │
   │                                                              ▼     ▼
   │                                                        ┌─────────────────┐
   │                                                        │    BmsFrame     │
   │                                                        │ one snapshot of │
   │                                                        │  the whole pack │
   │                                                        └────────┬────────┘
   │                                                                 │ FrameReceived
   │                                                     ┌───────────┴───────────┐
   │                                                     ▼                       ▼
   │                                              Form1 (the screen)    CSV log (planned)
   │                                                     ▲              1 BmsFrame = 1 row
   │                                                  Limits
```

The intended system should function in this order:

1. The BMS firmware broadcasts **CAN messages** onto the bike's CAN bus.
2. A **USB-to-CAN adapter** connects the bus to the laptop.
3. A **source** class receives the messages. _While the hardware is being built, a **simulator** stands in for it and can be used when hardware is unavailable_.
4. The **decoder** turns the raw bytes into real values (volts, °C) and collates several CAN messages into one **`BmsFrame`**: that is a complete snapshot of the pack at a instant.
5. Each `BmsFrame` goes to the **screen** (`Form1`) and can be stored into a **CSV file**.
6. **`Limits`** holds the thresholds that decide what counts as a fault or warning- determines what colour each cell voltage/ faults show up on screen.

> **To confirm with the firmware team:** earlier project notes preferred **USB CDC** (the STM32 appears to the laptop as a virtual COM port) instead of a USB-to-CAN adapter. The rest of the software is the same either way; only the source class changes (`SerialBmsSource` instead of `CanBmsSource`).

---

## 3. Each part of the system, explained

### 3.1 Input: CAN messages

Every CAN message has three parts:

| Part | Meaning |
|---|---|
| **ID** | Says *what kind* of message it is (e.g. `0x100` = cells 1–4). A lower ID also means higher priority on the bus. |
| **Length** | Number of data bytes, 0–8 |
| **Data** | The values, packed as raw bytes, e.g. `80 0E 79 0E 72 0E 7E 0E` |

The bytes mean nothing on their own. The **DBC file** (agreed with the firmware team) is the dictionary that says which bytes hold which value, and how to scale them:

> **physical value = raw value × factor + offset**
Example: bytes `80 0E`, little-endian, read as `0x0E80` = 3712. With factor 0.001, that's **3.712 V**.


### 3.2 `IBmsSource`: the contract (`IBmsSource.cs`)

`IBmsSource` is a set of rules, known as an "interface", that every data source must follow:

> "Anything that calls itself a BMS source must have a `Start()` method, a `Stop()` method, and a `FrameReceived` event that pushes out `BmsFrame`s."

- `Start()`: begin delivering readings (open the adapter or port, or start the simulator)
- `Stop()`: stop delivering them and release the adapter or port. This only affects the laptop NOT the BMS ( bms can keep running)
- `FrameReceived`: this signal "this reading is ready" so the screen knows to expect something.

The compiler checks these rules **when the program is built**. If a source is missing one of them, the program won't build. At runtime the interface does nothing.

**Why it exists:** the screen only ever talks to "an `IBmsSource`", never to a specific source and it makes switching between the simulator and the real hardware a simple one-line change in `Form1.cs`, and the screen code can stay same.
_Think of it like a plug socket standard: a kettle and a phone charger are completely different inside, but both fit the same socket._ 

### 3.3 Sources: real and simulated

| Source | What it does | Tests | Status |
|---|---|---|---|
| `SimulatedBmsSource` | Invents realistic readings (pack slowly discharging with noise) and puts them straight into a `BmsFrame`. Has switches to inject faults (over-temp, low cell, comms loss). | The screen | Planned |
| `SimulatedCanSource` | Generates fake *raw CAN messages*, exactly as the bike would send them, and feeds them to the same decoder as the real source. | Decoder + screen | Planned (needs DBC) |
| `CanBmsSource` | Receives real CAN messages from the USB-to-CAN adapter. | Everything, on the bike | Planned (needs hardware signoff) |


### 3.4 `CanBmsDecoder`: raw bytes → values (planned)

- Receives each CAN message (ID + bytes).
- Uses the DBC rules to decode it into real values.
- Stores the values until it has a **full set**. With 8 bytes per message, one message only holds about 4 cell voltages, so a full pack reading spans several messages.
- Builds a `BmsFrame` from the full set and sends it out through `FrameReceived`.

The decoder is kept in its own class so the real source and the CAN simulator share **the same decoding code**. Testing with the simulator therefore genuinely tests what will run on the bike.

### 3.5 `BmsFrame`: one snapshot of the pack (`BmsFrame.cs`)

`BmsFrame` doesn't actually do anything lol. It's a container: one complete reading of the whole pack at a single moment.

| Contains now | To be added ??|
|---|---|
| Time stamp | Pack current |
| All cell voltages | State of charge (SoC) |
| All temperatures | BMS state (idle / charging / driving) |
| Fault code | |
| Calculated: pack voltage, min/max cell, cell imbalance (max − min) | |

A `BmsFrame` is built from several CAN messages. This keeps CAN details out of the screen code, means the display updates all at once rather than half-new, half-old, and gives exactly one row per snapshot in the csv log.

> Note: CAN also calls each message a "frame".

### 3.6 `Form1`: the screen (`Form1.cs`)

This is the front end the user sees. It listens for `FrameReceived` and, for each new `BmsFrame`:

- updates a tile for each cell and each temperature sensor, coloured **green** (normal), **amber** (close to a limit) or **red** (outside a limit);
- shows a large status bar: **ALL OK**, **FAULT: …** (in plain words), **COMMS LOST** (no data for over 2 seconds) or **STOPPED**;
- shows a summary line: pack voltage, min/max cell, imbalance and time of the last update.

The fault-injection switches only appear when the source is the simulator.

*TAKE CARE: (`Form1.Designer.cs` is generated automatically by Visual Studio. Don't edit it by hand.)*

### 3.7 `Limits`: thresholds and fault codes (`Limits.cs`)

All the numbers that define the safety conditions live in one place:

- cell over-voltage and under-voltage limits;
- maximum temperature;
- fault codes and their plain-English names.

Fault codes are **bit flags** (1 = over-voltage, 2 = under-voltage, 4 = over-temperature, …), so several faults can be reported at once. For example, a code of 6 means under-voltage *and* over-temperature.

With real hardware, the **firmware decides** whether there's a fault and sends the code. The software uses `Limits` to colour the display and to name the faults. The simulator also uses it to imitate the firmware.

> TAKE REAL CARE: The current values are **placeholders**. They must be set from the real cell datasheet and the team's agreed limits, and kept consistent with the firmware.

### 3.8 CSV log (planned)

Each charging or test session will be saved as a CSV file on the laptop (**1 `BmsFrame` = 1 row**) that opens in Excel or MATLAB. Planned extensions include session IDs, fault-event records and a viewer for comparing past charging cycles.

---

## 4. File list

| File | Job | Status |
|---|---|---|
| `IBmsSource.cs` | The contract every data source must follow | Planned |
| `SimulatedBmsSource.cs` | Fake finished readings, with fault injection | Planned |
| `BmsFrame.cs` | One snapshot of the whole pack | Planned (SoC and current to add) |
| `Limits.cs` | Thresholds and fault codes | Planned (placeholder values TBD) |
| `Form1.cs` | The output on the screen | Plan |
| `CanBmsDecoder.cs` | Decodes CAN messages into `BmsFrame`s using the DBC | Planned |
| `SimulatedCanSource.cs` | Fake raw CAN messages | Planned |
| `CanBmsSource.cs` | Real USB-to-CAN adapter | Planned |
| CSV logging | Saves each session to file | Planned |

---

## 5. Running it

1. Install **Visual Studio Community** with the **".NET desktop development"** workload.
2. Open the solution (`MotoBmsMonitor.sln`) and press **F5**.  
3. Rest is TBD as the backend develops

```csharp
private readonly IBmsSource _source = new SimulatedBmsSource(CellCount, TempCount);
// becomes
private readonly IBmsSource _source = new CanBmsSource(/* adapter settings */);
```

Set `CellCount` and `TempCount` at the top of `Form1.cs` to match the pack.

---

## 6. Glossary

| Term | Meaning |
|---|---|
| **CAN bus** | The two-wire network the bike's controllers use to talk to each other. Every message is broadcast to every device. |
| **DBC file** | The dictionary describing every CAN message: its ID, where each value sits in the bytes, and its scaling and units. |
| **Interface** | In C#, a set of rules a class promises to follow (here, `IBmsSource`). |
| **Event** | A "something happened" signal other code can listen for (here, `FrameReceived`, meaning "new reading ready"). |
| **Class** | A self-contained piece of code describing one thing (e.g. `BmsFrame`, `SimulatedBmsSource`). Usually one per `.cs` file. |
| **Compile / build** | Turning the `.cs` text files into a runnable `.exe`. Many mistakes are caught at this stage. |
| **SoC** | State of charge: how full the pack is, in %. |
| **Imbalance** | Highest cell voltage minus lowest. A growing imbalance over several sessions can point to a weak cell. |
