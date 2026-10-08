# TradePilot Companions

Open-source MT4 and MT5 chart tools by Tinashe Chimanikire. Fork this repository to inspect, build or modify the companions under the MIT licence.

## What is included

Position Sizer, Daily Performance and Daily Loss Limit, Current Basket and Carry-over, Point Measurer, Pending Orders, chart binding and the optional local TradePilot desktop connection.

The TradePilot desktop subscription application is a separate private project available through Microsoft Store. Its source, payment administration, account database, passwords and connection files are not in this repository.

## Build and try the tools

1. Fork or clone this repository.
2. In your broker terminal, choose File → Open Data Folder.
3. Copy the relevant platform source and all its `.mqh` files into a dedicated folder under `MQL4/Experts` or `MQL5/Experts`.
4. Open `TradePilot.mq4` in MT4 MetaEditor, or `TradePilot.mq5` in MT5 MetaEditor, and compile with F7. MT5 also needs the standard libraries supplied with MetaEditor.
5. Start with a demo account and trading permissions OFF. Attach the compiled tool to a chart and review its panels.
6. Trading is a deliberate user action: review the terminal toolbar and each chart advisor's F7 permissions only when ready to test. Pending Orders starts OFF. Existing saved choices can differ.
7. For managed copying, register the account in the TradePilot desktop app. The local connection starts disabled and its account ID/key defaults are empty; this source archive does not contain a working account connection.

## Development status

This is development source, not a certified production release. MT4 and MT5 compilation and isolated desktop regression checks are recorded in the private project. 235 regression checks pass and both companions compile without errors or warnings. Latest native layout, spread consent and broker execution checks remain release gates. Broker execution, margin calculations and copied demo orders need deliberate testing with fresh prices. A displayed estimate or accepted pending order is not proof that a trade executed.

## Execution categories

Direct MT4/MT5 trades: Manual execution. Trades placed through TradePilot controls: System Manual Execution. Automated/copied trades: System execution. The new category requires a matching desktop build for imports; older clients may reject it. Missing origin information remains Pending.

## Licence

MIT. Keep the copyright and licence notice when sharing or reusing this source. MetaTrader and broker-supplied libraries are not included and retain their own terms.
