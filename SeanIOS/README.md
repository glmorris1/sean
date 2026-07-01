# GhostTrade iOS

Native SwiftUI mobile charting and backtesting app inspired by professional trading terminals.

## Current Prototype

- Watchlist with symbol search
- Mobile chart view inspired by TradingView's iPhone chart: full-screen purple chart canvas, floating drawing tools, compact symbol/timeframe bar, and bottom navigation
- Candle, line, and area modes
- Moving average overlays
- Paper order ticket
- Backtesting tab with MA Cross, Breakout, and RSI Reversion strategies
- Equity curve, performance cards, and recent trades

## Build

Open `Sean.xcodeproj` in Xcode, or build from the command line:

```sh
xcodebuild -project Sean.xcodeproj -scheme Sean -destination 'generic/platform=iOS Simulator' build
```
