# Install TradePilot Companions

## 1. Get the source

On GitHub, choose **Fork** to keep your own copy. To install without creating a fork, choose **Code → Download ZIP**, then extract the ZIP. This repository contains source files; you compile them in your terminal's MetaEditor.

## 2. Choose the correct platform

Use the **MT4** folder for MetaTrader 4 and **MT5** for MetaTrader 5. They are separate builds and cannot be interchanged. Start on a demo account with AutoTrading/Algo Trading OFF.

## 3. Copy into your terminal

1. In the intended broker terminal, select **File → Open Data Folder**.
2. Open **MQL4 → Experts** for MT4, or **MQL5 → Experts** for MT5.
3. Create a folder named **TradePilot**.
4. Copy every file from the repository's matching MT4 or MT5 folder into that folder. Keep the main source and all `.mqh` helper files together. Do not copy the outer repository folder instead of these files.

Repeat this for each terminal installation you intend to use; each broker terminal may have its own data folder.

## 4. Compile

1. Open MetaEditor from the terminal's toolbar or **Tools → MetaQuotes Language Editor**.
2. In MetaEditor, open the copied **TradePilot.mq4** or **TradePilot.mq5**.
3. Press **F7** to compile. Here, F7 builds the code; it does not enable trading.
4. Check the compilation results for **0 errors**. Compilation produces `TradePilot.ex4` or `TradePilot.ex5` in the same folder.
5. Return to the terminal. In **Navigator → Expert Advisors**, right-click and select **Refresh**.

If helper files cannot be found, copy all matching `.mqh` files alongside the main file. MT5's `Trade/Trade.mqh` comes with MetaEditor; use the broker's current MT5 installation if that standard library is missing.

## 5. Attach and inspect

1. Open a chart, then drag **TradePilot** from Navigator onto it.
2. Keep trading permissions OFF while checking the panels.
3. For independent chart tools, leave **TP_LocalBridge = false** and the connection ID/key empty. A GitHub fork does not register an account or activate copying.
4. Confirm the Position Sizer, Daily Performance, Daily Loss Limit, Current Basket, Carry-over, Point Measurer and Pending Orders panels are readable.
5. If a chart already has another advisor, attaching TradePilot can replace it. Use a separate chart when both advisors are needed.

## 6. Enable trading only when ready

In the terminal, **F7 on the chart** opens the attached advisor's properties; this differs from compiling in MetaEditor.

- **MT4:** check the advisor's **Common → Allow live trading**, then deliberately enable the toolbar's **AutoTrading**.
- **MT5:** check the advisor's **Common → Allow Algo Trading**, then deliberately enable the toolbar's **Algo Trading**.

Check each chart's permissions. Broker/server restrictions still apply even when local permissions are enabled. Pending Orders starts OFF and must be turned on manually. Review risk, account deposit currency, stop loss, spread and margin before using Buy, Sell or Place Order. Spread OFF confirmation during Calculate only calculates a size; it does not place a trade.

## 7. Connect to the desktop app, if required

Install TradePilot desktop through its authorised Microsoft Store listing and use its account registration/terminal setup guide. The desktop creates the connection information and installs matching companions. Do not invent connection keys or publish generated connection files. Copying also depends on the desktop's approval rules, an authenticated platform reply and broker trading permissions.

## Updating and troubleshooting

Close the intended terminal before replacing compiled companions. Keep a copy of your previous source and compiled files, copy the complete new platform folder, compile again, then reopen and verify the panels with trading OFF. If managed by the desktop app, use its matching companion installation process instead.

If TradePilot does not appear in Navigator, verify you used **this terminal's** data folder, the compilation succeeded, and Navigator was refreshed. Check **Experts** and **Journal** for the actual error. A connected panel or successful compilation does not prove that an order executed.

## Development status

This is MIT-licensed development source. The latest build passes 237 desktop regression checks and both native compilations without errors or warnings. Remaining native checks, broker execution tests and final release packaging must pass before the next Microsoft submission. See [README](README.md) for repository scope and [Admin Guide](ADMIN-GUIDE.txt) for desktop administration.


## Current panel update confirmations
Daily Performance Update shows target changes in the selected mode, with the other two equivalents in brackets. Daily Loss Limit Update shows the change to its allowance in Cash or Percentage, with cash/percentage/risk-unit equivalents and Apply wins/losses ON or OFF. A risk-unit change of 0.5R means half the planned cash risk. Cancel does not save settings. Missing balance/risk equivalents show Pending. Main and Current Basket display switches start OFF; turning them ON does not enable trading. Zoom controls sit above Target mode.

These are development changes: complete native calculation and flicker verification remain pending. Keep terminal trading OFF during installation and layout checks.

## Checking results before a daily loss update
Before updating Daily Loss Limit, open Current Basket and check Wins, Losses, Trade count and closed Total P/L for the current broker day. Use those actual results when reviewing your allowance. Choose Apply wins and Apply losses deliberately: ON includes that result in progress toward the daily target; OFF leaves it out of target progress. These switches never remove trades from reports or exclude losses from the Daily Loss Limit safety check, which always counts both wins and losses plus open results. Press Daily Loss Limit Update, review the increase/decrease and both switch states, then choose Yes to save or No to cancel. Check Current Basket again after saving; older carry-over baskets remain separate.
