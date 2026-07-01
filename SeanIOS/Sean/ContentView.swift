import Charts
import SwiftUI
import UIKit

struct ContentView: View {
    @Bindable var auth: AuthService
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var store = MarketStore()
    @State private var paperTrading = PaperTradingService()
    @State private var selectedTab = 1
    @State private var showSettings = false
    @State private var isReplayMode = false
    @State private var isAwaitingReplayStart = false
    @State private var isChoosingReplayStartMethod = false
    @State private var replayStartIndex: Int?
    @State private var replayCurrentIndex: Int?
    @State private var replaySpeed: ReplaySpeed = .two
    @State private var replayUpdateInterval: ReplayUpdateInterval = .three
    @State private var isReplayPlaying = false
    @State private var replayCandleProgress = 1.0
    @State private var hideMainTabBarForBacktest = false
    @State private var backtestChooserSelection = "selectStart"
    @Namespace private var backtestChooserNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            if mainTabBarHidden {
                chartContent
            } else {
                TabView(selection: $selectedTab) {
                    WatchlistView(store: store, selectedTab: $selectedTab)
                        .tabItem { Label("Watchlist", systemImage: "bookmark.fill") }
                        .tag(0)

                    chartContent
                        .tabItem { Label("Chart", systemImage: "chart.bar.xaxis") }
                        .tag(1)

                    ExploreView()
                        .tabItem { Label("Explore", systemImage: "safari.fill") }
                        .tag(2)

                    BacktestView(store: store, paperTrading: paperTrading)
                        .tabItem {
                            Image("PaperTradeTabIcon")
                            Text("PaperTrade")
                        }
                        .tag(3)

                    Color.clear
                        .tabItem { Label("Backtest", systemImage: "backward.fill") }
                        .tag(4)
                }
                .toolbar(.visible, for: .tabBar)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.black.opacity(0.84))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.9), in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    }
                    .padding(.top, settingsButtonTopPadding)
                    .padding(.trailing, 14)
                }
                Spacer()
            }

            replayBottomBar
                .padding(.horizontal, 34)
                .padding(.bottom, -2)
                .opacity(replayIsActive ? 1 : 0)
                .allowsHitTesting(replayIsActive)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .task {
            configureUserScopedStorage()
            setSystemTabBarHidden(mainTabBarHidden)
            await store.loadSelectedSymbol()
            processPaperTradingCandles()
        }
        .task(id: replayPlaybackID) {
            await runReplayPlayback()
        }
        .task(id: marketRefreshID) {
            await runMarketDataRefreshLoop()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 4 {
                hideMainTabBarForBacktest = true
                backtestChooserSelection = "selectStart"
                setSystemTabBarHidden(true)
                selectedTab = 1
                toggleReplayControl()
            }
        }
        .onChange(of: store.selected.ticker) { _, _ in
            exitReplay()
            paperTrading.account.lastProcessedBarIndexBySymbol[store.selected.ticker] = store.candles.last?.index ?? -1
        }
        .onChange(of: store.selectedInterval) { _, _ in
            isReplayPlaying = false
            clampReplayToLoadedCandles()
        }
        .onChange(of: store.candles.count) { _, _ in
            clampReplayToLoadedCandles()
            processPaperTradingCandles()
        }
        .onChange(of: replayCurrentIndex) { _, _ in
            processPaperTradingCandles()
        }
        .onChange(of: mainTabBarHidden) { _, isHidden in
            setSystemTabBarHidden(isHidden)
        }
        .sheet(isPresented: $showSettings) {
            StrategyLibraryView(store: store, auth: auth)
        }
        .onChange(of: auth.currentUser?.id) { _, _ in
            configureUserScopedStorage()
        }
        .onChange(of: store.symbols) { _, _ in
            syncUserData()
        }
        .onChange(of: paperTrading.account) { _, _ in
            syncUserData()
        }
    }

    private func configureUserScopedStorage() {
        let userID = auth.currentUser?.email
        store.setUserID(userID)
        paperTrading.setUserID(userID)
        Task { await pullUserDataIfAvailable() }
    }

    private func pullUserDataIfAvailable() async {
        guard let user = auth.currentUser,
              let snapshot = try? await UserDataSyncService.fetchSnapshot(for: user) else {
            return
        }
        store.replaceWatchlist(with: snapshot.watchlist)
        paperTrading.account = snapshot.paperTradingAccount
    }

    private func syncUserData() {
        guard let user = auth.currentUser else { return }
        let snapshot = UserDataSnapshot(
            watchlist: store.persistedWatchlist,
            paperTradingAccount: paperTrading.account,
            updatedAt: Date()
        )
        Task {
            await UserDataSyncService.saveSnapshot(snapshot, for: user)
        }
    }

    @ViewBuilder
    private var replayBottomBar: some View {
        if isChoosingReplayStartMethod {
            backtestChooserBar
                .environment(\.colorScheme, .light)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: backtestChooserSelection)
        } else {
            replayControlBar
                .environment(\.colorScheme, .light)
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: replayIsActive)
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isReplayMode)
        }
    }

    private var replayControlBar: some View {
        HStack(spacing: 8) {
            Button {
                if isReplayMode || isAwaitingReplayStart {
                    exitReplay()
                } else {
                    toggleReplayControl()
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 18, weight: .black))
                    Text("Back")
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(width: 44, height: 50)
                .foregroundStyle(.black.opacity(0.88))
            }
            .buttonStyle(.plain)

            Group {
                if isReplayMode {
                    VStack(spacing: 1) {
                        Text(replayDateLabel)
                            .font(.system(size: 11, weight: .semibold))
                        Text(replayClockLabel)
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                    }
                } else {
                    Text("Choose candle to start")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .center)

            if isReplayMode {
                Button { stepReplayBack() } label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 24, height: 32)
                }
                .disabled(!canStepReplayBack)

                Button { toggleReplayPlayback() } label: {
                    Image(systemName: isReplayPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 21, weight: .black))
                        .frame(width: 34, height: 36)
                }
                .disabled(!canStepReplayForward && !isReplayPlaying)

                Button { stepReplayForward() } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 24, height: 32)
                }
                .disabled(!canStepReplayForward)

                Menu {
                    ForEach(ReplaySpeed.allCases) { speed in
                        Button {
                            replaySpeed = speed
                        } label: {
                            Label(speed.rawValue, systemImage: replaySpeed == speed ? "checkmark" : "")
                        }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text("Speed")
                            .font(.system(size: 7, weight: .bold))
                        Text(replaySpeed.rawValue)
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 27, height: 27)
                            .background(.black.opacity(0.86), in: Circle())
                    }
                    .frame(width: 38)
                }

                Menu {
                    ForEach(ReplayUpdateInterval.allCases) { interval in
                        Button {
                            replayUpdateInterval = interval
                        } label: {
                            Label(interval.label, systemImage: replayUpdateInterval == interval ? "checkmark" : "")
                        }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text("Updates")
                            .font(.system(size: 7, weight: .bold))
                        Text("\(replayUpdateInterval.rawValue)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 27, height: 27)
                            .background(.black.opacity(0.86), in: Circle())
                    }
                    .frame(width: 44)
                }
            }
        }
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(.black.opacity(0.88))
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.58), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 7)
    }

    private var backtestChooserBar: some View {
        HStack(spacing: 0) {
            backtestChooserButton(id: "selectStart", title: "Select Start", systemImage: "scope") {
                isChoosingReplayStartMethod = false
                isAwaitingReplayStart = true
                isReplayMode = false
                isReplayPlaying = false
                replayStartIndex = nil
                replayCurrentIndex = nil
                replayCandleProgress = 1
            }

            backtestChooserButton(id: "random", title: "Random", systemImage: "shuffle") {
                selectRandomReplayStart()
            }

            backtestChooserButton(id: "back", title: "Back", systemImage: "chevron.backward") {
                exitReplay()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.58), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 7)
    }

    private func backtestChooserButton(id: String, title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                backtestChooserSelection = id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                action()
            }
        } label: {
            ZStack {
                if backtestChooserSelection == id {
                    Capsule()
                        .fill(.white.opacity(0.36))
                        .background(.thinMaterial, in: Capsule())
                        .matchedGeometryEffect(id: "backtestChooserSelection", in: backtestChooserNamespace)
                        .overlay(Capsule().stroke(.white.opacity(0.52), lineWidth: 1))
                        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
                }

                VStack(spacing: 3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .bold))
                        .frame(height: 22)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(.black.opacity(0.88))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
    }

    private var settingsButtonTopPadding: CGFloat {
        verticalSizeClass == .compact ? 10 : -6
    }

    private var chartContent: some View {
        MobileChartView(
            store: store,
            paperTrading: paperTrading,
            isReplayMode: $isReplayMode,
            isAwaitingReplayStart: $isAwaitingReplayStart,
            isChoosingReplayStartMethod: $isChoosingReplayStartMethod,
            replayStartIndex: $replayStartIndex,
            replayCurrentIndex: $replayCurrentIndex,
            replaySpeed: $replaySpeed,
            replayUpdateInterval: $replayUpdateInterval,
            isReplayPlaying: $isReplayPlaying,
            replayCandleProgress: $replayCandleProgress
        )
    }

    private func replayChoiceButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .black))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(.white.opacity(0.36), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var replayIsActive: Bool {
        isReplayMode || isAwaitingReplayStart || isChoosingReplayStartMethod
    }

    private var mainTabBarHidden: Bool {
        hideMainTabBarForBacktest || replayIsActive
    }

    private var replayPlaybackID: String {
        "\(isReplayPlaying)-\(replaySpeed.rawValue)-\(replayUpdateInterval.rawValue)-\(store.candles.count)"
    }

    private var marketRefreshID: String {
        "\(store.selected.ticker)-\(store.selectedInterval.rawValue)"
    }

    private var marketRefreshInterval: Duration {
        switch store.selectedInterval {
        case .oneDay:
            return .seconds(60)
        case .oneHour, .fourHours:
            return .seconds(15)
        default:
            return .seconds(3)
        }
    }

    @MainActor
    private func runMarketDataRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: marketRefreshInterval)
            guard !Task.isCancelled else { break }
            await store.refreshSelectedSymbol()
            clampReplayToLoadedCandles()
            processPaperTradingCandles()
        }
    }

    private func setSystemTabBarHidden(_ hidden: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .flatMap { tabBars(in: $0) }
                .forEach { tabBar in
                    tabBar.isHidden = hidden
                    tabBar.alpha = hidden ? 0 : 1
                }
        }
    }

    private func tabBars(in view: UIView) -> [UITabBar] {
        var result = view is UITabBar ? [view as! UITabBar] : []
        for subview in view.subviews {
            result.append(contentsOf: tabBars(in: subview))
        }
        return result
    }

    private var replayTimeLabel: String {
        guard let replayCurrentIndex, store.candles.indices.contains(replayCurrentIndex) else {
            return "--"
        }
        let date = store.candles[replayCurrentIndex].date
        return store.selectedInterval == .oneDay ? date.chartLabel : date.crosshairIntradayLabel
    }

    private var replayDateLabel: String {
        guard let replayCurrentIndex, store.candles.indices.contains(replayCurrentIndex) else {
            return "--"
        }
        return store.candles[replayCurrentIndex].date.shortChartLabel
    }

    private var replayClockLabel: String {
        guard let replayCurrentIndex, store.candles.indices.contains(replayCurrentIndex) else {
            return "--"
        }
        return store.candles[replayCurrentIndex].date.intradayChartLabel
    }

    private var canStepReplayForward: Bool {
        guard isReplayMode, let replayCurrentIndex else { return false }
        return replayCurrentIndex < store.candles.count - 1
    }

    private var canStepReplayBack: Bool {
        guard isReplayMode, let replayCurrentIndex else { return false }
        return replayCurrentIndex > (replayStartIndex ?? 0)
    }

    private func toggleReplayControl() {
        if replayIsActive {
            exitReplay()
        } else {
            hideMainTabBarForBacktest = true
            backtestChooserSelection = "selectStart"
            setSystemTabBarHidden(true)
            isReplayPlaying = false
            isAwaitingReplayStart = true
            isChoosingReplayStartMethod = true
            isReplayMode = false
            replayStartIndex = nil
            replayCurrentIndex = nil
            replayCandleProgress = 1
        }
    }

    private func exitReplay() {
        isReplayPlaying = false
        isReplayMode = false
        isAwaitingReplayStart = false
        isChoosingReplayStartMethod = false
        hideMainTabBarForBacktest = false
        replayStartIndex = nil
        replayCurrentIndex = nil
        replayCandleProgress = 1
    }

    private func clampReplayToLoadedCandles() {
        guard replayIsActive else { return }
        guard !store.candles.isEmpty else {
            isReplayPlaying = false
            isReplayMode = false
            isAwaitingReplayStart = true
            isChoosingReplayStartMethod = true
            replayStartIndex = nil
            replayCurrentIndex = nil
            replayCandleProgress = 1
            return
        }

        let lastIndex = store.candles.count - 1
        if let replayStartIndex {
            self.replayStartIndex = min(max(replayStartIndex, 0), lastIndex)
        }
        if let replayCurrentIndex {
            self.replayCurrentIndex = min(max(replayCurrentIndex, 0), lastIndex)
        }
        replayCandleProgress = 1
    }

    private func selectRandomReplayStart() {
        guard store.candles.count > 1 else { return }
        let lastDate = store.candles.last?.date ?? Date()
        let threshold = Calendar.current.date(byAdding: .year, value: -3, to: lastDate) ?? store.candles[0].date
        let lastSelectableIndex = max(0, store.candles.count - 2)
        let candidates = store.candles.enumerated()
            .filter { index, candle in
                index <= lastSelectableIndex && candle.date >= threshold
            }
            .map(\.offset)
        let selected = candidates.randomElement() ?? Int.random(in: 0...lastSelectableIndex)

        isReplayPlaying = false
        replayStartIndex = selected
        replayCurrentIndex = selected
        replayCandleProgress = 1
        isReplayMode = true
        isAwaitingReplayStart = false
        isChoosingReplayStartMethod = false
    }

    private func stepReplayForward() {
        guard isReplayMode, let current = replayCurrentIndex else {
            isReplayPlaying = false
            return
        }
        guard current < store.candles.count - 1 else {
            isReplayPlaying = false
            return
        }
        replayCurrentIndex = min(current + replayUpdateInterval.rawValue, store.candles.count - 1)
        replayCandleProgress = 1
        processPaperTradingCandles()
        if replayCurrentIndex == store.candles.count - 1 {
            isReplayPlaying = false
        }
    }

    private func stepReplayBack() {
        guard isReplayMode, let current = replayCurrentIndex else {
            isReplayPlaying = false
            return
        }
        replayCurrentIndex = max(replayStartIndex ?? 0, current - replayUpdateInterval.rawValue)
        replayCandleProgress = 1
        isReplayPlaying = false
        paperTrading.resyncForReplay(symbol: store.selected.ticker, through: paperVisibleCandles)
    }

    private func toggleReplayPlayback() {
        guard isReplayMode, let current = replayCurrentIndex else { return }
        isReplayPlaying = current < store.candles.count - 1 ? !isReplayPlaying : false
    }

    @MainActor
    private func runReplayPlayback() async {
        guard isReplayPlaying else { return }
        while !Task.isCancelled, isReplayPlaying {
            for _ in 0..<replayUpdateInterval.rawValue {
                guard !Task.isCancelled, isReplayPlaying else { break }
                guard let current = replayCurrentIndex, current < store.candles.count - 1 else {
                    isReplayPlaying = false
                    break
                }

                replayCurrentIndex = current + 1
                replayCandleProgress = 0
                processPaperTradingCandles()

                let frames = 12
                for frame in 1...frames {
                    try? await Task.sleep(for: replaySpeed.interval / frames)
                    guard !Task.isCancelled, isReplayPlaying else { break }
                    replayCandleProgress = Double(frame) / Double(frames)
                }

                if replayCurrentIndex == store.candles.count - 1 {
                    isReplayPlaying = false
                    break
                }
            }
        }
    }

    private var paperVisibleCandles: [Candle] {
        guard isReplayMode, let replayCurrentIndex, !store.candles.isEmpty else {
            return store.candles
        }
        let end = min(max(replayCurrentIndex, 0), store.candles.count - 1)
        return Array(store.candles[0...end])
    }

    private func processPaperTradingCandles() {
        paperTrading.configureInstrument(store.selected)
        paperTrading.processVisibleCandles(paperVisibleCandles, symbol: store.selected.ticker, isReplayMode: isReplayMode)
    }
}

private struct WatchlistView: View {
    @Bindable var store: MarketStore
    @Binding var selectedTab: Int
    @State private var query = ""
    @State private var searchResults: [MarketSymbol] = []
    @State private var isSearching = false
    @State private var searchError: String?

    private var isSearchingSymbols: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearchingSymbols {
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView("Searching symbols")
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    } else if searchResults.isEmpty {
                        ContentUnavailableView(
                            "No Symbols Found",
                            systemImage: "magnifyingglass",
                            description: Text(searchError ?? "Try a ticker or company name.")
                        )
                    } else {
                        ForEach(searchResults) { symbol in
                            searchResultRow(symbol)
                        }
                    }
                } else {
                    ForEach(store.symbols) { symbol in
                        watchlistRow(symbol)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.removeFromWatchlist(symbol)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.removeFromWatchlist(store.symbols[index])
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search symbols")
            .navigationTitle("Watchlist")
            .task(id: query) {
                await searchSymbols()
            }
        }
    }

    private func watchlistRow(_ symbol: MarketSymbol) -> some View {
        Button {
            Task {
                await store.select(symbol)
                selectedTab = 1
            }
        } label: {
            symbolRow(symbol)
        }
    }

    private func searchResultRow(_ symbol: MarketSymbol) -> some View {
        Button {
            Task {
                await store.select(symbol)
                selectedTab = 1
            }
        } label: {
            HStack(spacing: 10) {
                Button {
                    store.addToWatchlist(symbol)
                } label: {
                    Image(systemName: store.isInWatchlist(symbol) ? "star.fill" : "star")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(store.isInWatchlist(symbol) ? .yellow : .secondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderless)
                .disabled(store.isInWatchlist(symbol))

                symbolRow(symbol)
            }
        }
    }

    private func symbolRow(_ symbol: MarketSymbol) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol.ticker)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(symbol.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(symbol.exchange)
                    Text(symbol.assetBadge)
                    if let quoteCurrency = symbol.quoteCurrency {
                        Text(quoteCurrency)
                    }
                    if let contractType = symbol.contractType {
                        Text(contractType.capitalized)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(symbolBadgeColor(symbol))
                .lineLimit(1)
                if let metadataText = symbolMetadataText(symbol) {
                    Text(metadataText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(symbol.last > 0 ? symbol.last.priceText : (symbol.isFutures || symbol.isProviderBackedInstrument ? "Historical" : "Live"))
                    .font(.headline.monospacedDigit())
                if symbol.isFutures || symbol.isProviderBackedInstrument {
                    Text(symbol.futures?.currency ?? symbol.quoteCurrency ?? "USD")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(symbol.changePercent.percentText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(symbol.changePercent >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func symbolBadgeColor(_ symbol: MarketSymbol) -> Color {
        switch symbol.assetClass {
        case "futures":
            return .orange
        case "forex":
            return .blue
        case "spot_metal":
            return .yellow
        case "crypto":
            return .purple
        default:
            return .secondary
        }
    }

    private func symbolMetadataText(_ symbol: MarketSymbol) -> String? {
        if let provider = symbol.provider,
           let timeframes = symbol.availableTimeframes,
           !timeframes.isEmpty {
            return "\(provider) · \(timeframes.joined(separator: ", "))"
        }
        return symbol.dataAvailability
    }

    private func searchSymbols() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }

        isSearching = true
        searchError = nil
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            searchResults = try await MarketDataService.searchSymbols(matching: trimmed)
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchError = error.localizedDescription
        }
        isSearching = false
    }
}

private struct MobileChartView: View {
    @Bindable var store: MarketStore
    @Bindable var paperTrading: PaperTradingService
    @Binding var isReplayMode: Bool
    @Binding var isAwaitingReplayStart: Bool
    @Binding var isChoosingReplayStartMethod: Bool
    @Binding var replayStartIndex: Int?
    @Binding var replayCurrentIndex: Int?
    @Binding var replaySpeed: ReplaySpeed
    @Binding var replayUpdateInterval: ReplayUpdateInterval
    @Binding var isReplayPlaying: Bool
    @Binding var replayCandleProgress: Double
    @State private var chartStyle: ChartStyle = .candles
    @State private var showIndicators = true
    @State private var showVolume = true
    @State private var selectedCurrency = "USD"
    @State private var activeTool: DrawingTool?
    @State private var drawings: [ChartDrawing] = []
    @State private var drawingHistory: [[ChartDrawing]] = []
    @State private var toolRailCenter: CGPoint?
    @State private var toolRailGrabOffset: CGSize?
    @State private var toolRailOrientation: ToolRailOrientation = .vertical
    @State private var lastToolRailLandscapeState: Bool?
    @State private var isToolRailCollapsed = false
    @State private var didDragToolRail = false
    @State private var lastVisibleChartCandle: Candle?
    @State private var paperOrderNotice: String?

    private var chartInk: Color {
        store.chartBackgroundTheme.isLight ? .black : .white
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                TradingChartCanvas(
                    symbol: store.selected,
                    paperTrading: paperTrading,
                    candles: store.candles,
                    style: chartStyle,
                    showIndicators: showIndicators,
                    showVolume: showVolume,
                    interval: store.selectedInterval,
                    backgroundTheme: store.chartBackgroundTheme,
                    isLoading: store.isLoading,
                    errorMessage: store.errorMessage,
                    activeTool: $activeTool,
                    drawings: $drawings,
                    isReplayMode: $isReplayMode,
                    isAwaitingReplayStart: $isAwaitingReplayStart,
                    isChoosingReplayStartMethod: $isChoosingReplayStartMethod,
                    replayStartIndex: $replayStartIndex,
                    replayCurrentIndex: $replayCurrentIndex,
                    replaySpeed: $replaySpeed,
                    replayUpdateInterval: $replayUpdateInterval,
                    isReplayPlaying: $isReplayPlaying,
                    replayCandleProgress: $replayCandleProgress,
                    lastVisibleCandle: $lastVisibleChartCandle,
                    recordDrawingHistory: recordDrawingHistory,
                    notifyOrderPlacedOnCurrentPrice: showCurrentPriceOrderNotice
                )
                .ignoresSafeArea(edges: .top)

                chartHeader
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    .zIndex(2)

                if activeTool == .paperTrade {
                    paperTradeQuickTicket
                        .padding(.top, 108)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .zIndex(4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let paperOrderNotice {
                    Text(paperOrderNotice)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.88), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                        .padding(.top, activeTool == .paperTrade ? 166 : 112)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .zIndex(5)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                rightToolRail(in: geometry)
                    .position(toolRailCenter ?? defaultToolRailCenter(in: geometry))
                    .zIndex(3)
            }
            .background(
                LinearGradient(
                    colors: store.chartBackgroundTheme.colors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .coordinateSpace(name: "chartSurface")
            .onAppear {
                applyDefaultToolRailOrientation(for: geometry)
                paperTrading.requestNotificationPermission()
            }
            .onChange(of: geometry.size) { _, _ in
                applyDefaultToolRailOrientation(for: geometry)
            }
        }
    }

    private var chartHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(store.selected.ticker)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(chartInk)
                Text(store.selected.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(chartInk.opacity(0.68))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    Circle()
                        .fill(Self.usMarketIsOpen(at: timeline.date) ? .teal : .gray)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().fill(.white.opacity(0.18)).padding(6))
                }
            }

            HStack(spacing: 8) {
                Text(store.selected.last > 0 ? store.selected.last.priceText : "--")
                Text(store.selected.changePercent.percentText)
            }
            .font(.system(size: 26, weight: .bold).monospacedDigit())
            .foregroundStyle(chartInk)
            .shadow(color: store.chartBackgroundTheme.isLight ? .white.opacity(0.5) : .black.opacity(0.8), radius: 10)
        }
    }

    private var paperTradeQuickTicket: some View {
        HStack(spacing: 10) {
            Button {
                createPaperSetup(direction: .short)
            } label: {
                Text("Sell")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 76, height: 36)
                    .background(.red, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            TextField("Qty", value: $paperTrading.ticketQuantity, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 17, weight: .black).monospacedDigit())
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 86, height: 44)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 1))

            Button {
                createPaperSetup(direction: .long)
            } label: {
                Text("Buy")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 76, height: 36)
                    .background(.green, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.black.opacity(0.88), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }

    private var activePaperTradeCandle: Candle? {
        if isReplayMode, let lastVisibleChartCandle {
            return lastVisibleChartCandle
        }
        if isReplayMode, let replayCurrentIndex, store.candles.indices.contains(replayCurrentIndex) {
            return store.candles[replayCurrentIndex]
        }
        return store.candles.last
    }

    private var isViewingHistoricalPriceInNormalMode: Bool {
        guard !isReplayMode,
              let latest = store.candles.last,
              let lastVisibleChartCandle else {
            return false
        }
        return lastVisibleChartCandle.index < latest.index
    }

    private func createPaperSetup(direction: TradeDirection) {
        guard let candle = activePaperTradeCandle else { return }
        if isViewingHistoricalPriceInNormalMode {
            showCurrentPriceOrderNotice()
        }
        paperTrading.configureInstrument(store.selected)
        let recentCandles = store.candles.suffix(120)
        let recentHigh = recentCandles.map(\.high).max() ?? candle.close
        let recentLow = recentCandles.map(\.low).min() ?? candle.close
        let range = max(recentHigh - recentLow, 0.01)
        let offset = max(candle.close * 0.0005, range * 0.012, 0.01)
        let stopLoss = direction == .long ? candle.close - offset : candle.close + offset
        let takeProfit = direction == .long ? candle.close + offset : candle.close - offset
        _ = paperTrading.createChartSetupOrder(
            symbol: store.selected.ticker,
            direction: direction,
            price: candle.close,
            candle: candle,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            isReplayTrade: isReplayMode
        )
        activeTool = nil
    }

    private func showCurrentPriceOrderNotice() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
            paperOrderNotice = "Order placed on current price"
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.2)) {
                paperOrderNotice = nil
            }
        }
    }


    private static func usMarketIsOpen(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute,
              (2...6).contains(weekday) else {
            return false
        }

        let minutesAfterMidnight = hour * 60 + minute
        return minutesAfterMidnight >= (9 * 60 + 30) && minutesAfterMidnight < (16 * 60)
    }

    private var indicatorLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Vol 20")
                if showVolume {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(.purple.opacity(0.95))
                        .padding(7)
                        .background(.purple.opacity(0.25), in: Circle())
                }
            }
            HStack {
                Text("VWAP Session")
                Spacer()
                Image(systemName: showIndicators ? "eye" : "eye.slash")
            }
            HStack {
                Text("MA 20 / MA 50")
                Spacer()
                Image(systemName: showIndicators ? "eye" : "eye.slash")
            }
            HStack {
                Text("Backtest Signals")
                Spacer()
                Image(systemName: "eye.slash")
            }
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(chartInk.opacity(0.46))
        .frame(width: 248)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private var currencyButton: some View {
        Menu {
            Button("USD") { selectedCurrency = "USD" }
            Button("EUR") { selectedCurrency = "EUR" }
            Button("BTC") { selectedCurrency = "BTC" }
        } label: {
            HStack(spacing: 12) {
                Text(selectedCurrency)
                    .font(.title3.bold())
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
            }
            .foregroundStyle(chartInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func rightToolRail(in geometry: GeometryProxy) -> some View {
        Group {
            if toolRailOrientation == .vertical {
                verticalToolRailContent(in: geometry)
            } else {
                horizontalToolRailContent(in: geometry)
            }
        }
        .foregroundStyle(.white.opacity(0.84))
        .padding(.vertical, toolRailOrientation == .vertical ? 10 : 6)
        .padding(.horizontal, toolRailOrientation == .vertical ? 0 : 8)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isToolRailCollapsed)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: toolRailOrientation)
    }

    private func applyDefaultToolRailOrientation(for geometry: GeometryProxy) {
        let isLandscape = geometry.size.width > geometry.size.height
        guard lastToolRailLandscapeState != isLandscape else { return }

        lastToolRailLandscapeState = isLandscape
        let newOrientation: ToolRailOrientation = isLandscape ? .horizontal : .vertical
        toolRailOrientation = newOrientation
        toolRailCenter = clampedToolRailCenter(defaultToolRailCenter(in: geometry), in: geometry, orientation: newOrientation)
    }

    @ViewBuilder
    private func verticalToolRailContent(in geometry: GeometryProxy) -> some View {
        if isToolRailCollapsed {
            VStack(spacing: 7) {
                intervalRailMenu
                railActionButton(paperTradeToolAction)
                railDivider(isVertical: true, opacity: 0.18)
                railDragHandle(in: geometry)
            }
        } else if geometry.size.width > geometry.size.height {
            ScrollView(.vertical, showsIndicators: false) {
                verticalToolRailButtons(in: geometry)
            }
            .frame(height: max(96, toolRailSize(in: geometry, orientation: .vertical).height - 20))
        } else {
            verticalToolRailButtons(in: geometry)
        }
    }

    private func verticalToolRailButtons(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 7) {
            intervalRailMenu
            railDrawingButton(.brush, icon: "pencil.and.scribble")
            railDivider(isVertical: true, opacity: 0.22)

            ForEach(toolActions) { action in
                railActionButton(action)
            }

            railDivider(isVertical: true, opacity: 0.18)
            railDragHandle(in: geometry)
        }
    }

    private func horizontalToolRailContent(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 7) {
            if isToolRailCollapsed {
                HStack(spacing: 7) {
                    intervalRailMenu
                    railActionButton(paperTradeToolAction)
                }
                .frame(width: 92, height: 40)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        intervalRailMenu
                        railDrawingButton(.brush, icon: "pencil.and.scribble")
                        railDivider(isVertical: false, opacity: 0.22)

                        ForEach(toolActions) { action in
                            railActionButton(action)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .frame(width: max(150, horizontalToolRailWidth(in: geometry) - 52), height: 40)
            }

            railDragHandle(in: geometry)
        }
        .frame(width: isToolRailCollapsed ? 146 : horizontalToolRailWidth(in: geometry), height: 40)
    }

    private func railDivider(isVertical: Bool, opacity: Double) -> some View {
        Divider()
            .frame(width: isVertical ? 28 : 1, height: isVertical ? 1 : 28)
            .overlay(.white.opacity(opacity))
    }

    private func railActionButton(_ action: ChartToolAction) -> some View {
        Button {
            handleToolAction(action)
        } label: {
            toolActionIcon(action)
        }
        .accessibilityLabel(action.label)
        .buttonStyle(.plain)
    }

    private func railDragHandle(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(.white.opacity(0.86))
                        .frame(width: 5, height: 5)
                }
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(.white.opacity(0.86))
                        .frame(width: 5, height: 5)
                }
            }
        }
            .frame(width: 44, height: 28)
            .contentShape(Rectangle())
            .gesture(toolRailDragGesture(in: geometry))
            .accessibilityLabel("Move toolbar")
    }

    private func toolRailDragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("chartSurface"))
            .onChanged { value in
                let distance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                if distance > 4 {
                    didDragToolRail = true
                }

                if toolRailGrabOffset == nil {
                    let center = toolRailCenter ?? defaultToolRailCenter(in: geometry)
                    toolRailGrabOffset = CGSize(
                        width: value.startLocation.x - center.x,
                        height: value.startLocation.y - center.y
                    )
                }

                let grabOffset = toolRailGrabOffset ?? .zero
                toolRailCenter = clampedToolRailCenter(
                    CGPoint(
                        x: value.location.x - grabOffset.width,
                        y: value.location.y - grabOffset.height
                    ),
                    in: geometry
                )
            }
            .onEnded { _ in
                if !didDragToolRail {
                    toggleToolRailCollapsed(in: geometry)
                }
                toolRailGrabOffset = nil
                didDragToolRail = false
            }
    }

    private func toggleToolRailCollapsed(in geometry: GeometryProxy) {
        let oldSize = toolRailSize(in: geometry, orientation: toolRailOrientation, collapsed: isToolRailCollapsed)
        let newCollapsedState = !isToolRailCollapsed
        let newSize = toolRailSize(in: geometry, orientation: toolRailOrientation, collapsed: newCollapsedState)
        var center = toolRailCenter ?? defaultToolRailCenter(in: geometry)

        switch toolRailOrientation {
        case .vertical:
            center.y += (oldSize.height - newSize.height) / 2
        case .horizontal:
            center.x += (oldSize.width - newSize.width) / 2
        }

        isToolRailCollapsed = newCollapsedState
        toolRailCenter = clampedToolRailCenter(center, in: geometry)
    }

    private func defaultToolRailCenter(in geometry: GeometryProxy) -> CGPoint {
        let orientation = geometry.size.width > geometry.size.height ? ToolRailOrientation.horizontal : ToolRailOrientation.vertical
        let railSize = toolRailSize(in: geometry, orientation: orientation)
        let bounds = toolRailPlacementBounds(in: geometry, railSize: railSize)
        if orientation == .horizontal {
            let settingsButtonClearance: CGFloat = 70
            return CGPoint(
                x: min(max(geometry.size.width - settingsButtonClearance - railSize.width / 2, bounds.minX), bounds.maxX),
                y: min(max(bounds.minY + 8, bounds.minY), bounds.maxY)
            )
        }
        return CGPoint(
            x: bounds.maxX,
            y: (bounds.minY + bounds.maxY) / 2
        )
    }

    private func clampedToolRailCenter(_ center: CGPoint, in geometry: GeometryProxy) -> CGPoint {
        clampedToolRailCenter(center, in: geometry, orientation: toolRailOrientation)
    }

    private func clampedToolRailCenter(_ center: CGPoint, in geometry: GeometryProxy, orientation: ToolRailOrientation) -> CGPoint {
        let railSize = toolRailSize(in: geometry, orientation: orientation)
        let bounds = toolRailPlacementBounds(in: geometry, railSize: railSize)

        return CGPoint(
            x: min(max(center.x, bounds.minX), bounds.maxX),
            y: min(max(center.y, bounds.minY), bounds.maxY)
        )
    }

    private func toolRailPlacementBounds(in geometry: GeometryProxy, railSize: CGSize) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let railHalfWidth = railSize.width / 2
        let railHalfHeight = railSize.height / 2
        let horizontalMargin: CGFloat = 4
        let minX = railHalfWidth + horizontalMargin
        let maxX = max(minX, geometry.size.width - railHalfWidth - horizontalMargin)
        let minY = railHalfHeight + horizontalMargin
        let maxY = max(minY, geometry.size.height - railHalfHeight - horizontalMargin)
        return (minX, maxX, minY, maxY)
    }

    private func toolRailTopClearance(in geometry: GeometryProxy) -> CGFloat {
        geometry.size.width > geometry.size.height ? 8 : 74
    }

    private func toolRailBottomClearance(in geometry: GeometryProxy) -> CGFloat {
        guard geometry.size.width <= geometry.size.height else { return 12 }

        let topInset: CGFloat = 150
        let chartHeight: CGFloat = 470
        let volumeHeight: CGFloat = 96
        let dateAxisHeight: CGFloat = 18
        let bottomInset: CGFloat = 76
        let minimumContentHeight = topInset + chartHeight + volumeHeight + dateAxisHeight + bottomInset
        let sharedExtraSpacer = max(0, geometry.size.height - minimumContentHeight) / 2
        let volumeBottomY = sharedExtraSpacer + topInset + chartHeight + volumeHeight
        return max(82, geometry.size.height - volumeBottomY)
    }

    private func horizontalToolRailWidth(in geometry: GeometryProxy) -> CGFloat {
        max(220, min(geometry.size.width - 64, 428))
    }

    private func toolRailSize(in geometry: GeometryProxy, orientation: ToolRailOrientation) -> CGSize {
        toolRailSize(in: geometry, orientation: orientation, collapsed: isToolRailCollapsed)
    }

    private func toolRailSize(in geometry: GeometryProxy, orientation: ToolRailOrientation, collapsed: Bool) -> CGSize {
        if orientation == .horizontal {
            return CGSize(width: collapsed ? 162 : horizontalToolRailWidth(in: geometry), height: 52)
        }

        if collapsed {
            return CGSize(width: 62, height: 168)
        }

        let actionRows = toolActions.count + 3
        let approximateHeight = CGFloat(actionRows) * 28 + CGFloat(max(actionRows - 1, 0)) * 7 + 2 + 20
        let availableHeight = geometry.size.height - toolRailTopClearance(in: geometry) - toolRailBottomClearance(in: geometry)
        return CGSize(width: 62, height: min(max(120, approximateHeight), max(120, availableHeight)))
    }

    private var intervalRailMenu: some View {
        Menu {
            ForEach(CandleInterval.allCases) { interval in
                Button {
                    Task {
                        await store.selectInterval(interval)
                    }
                } label: {
                    HStack {
                        Text(interval.rawValue)
                        if interval == store.selectedInterval {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "clock")
                    .font(.system(size: 21, weight: .medium))
                Text(store.selectedInterval.rawValue)
                    .font(.system(size: 9, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(width: 44, height: 36)
            .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Candle interval")
    }

    private func railDrawingButton(_ tool: DrawingTool, icon: String) -> some View {
        Button {
            activeTool = activeTool == tool ? nil : tool
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 28)
                .foregroundStyle(.white.opacity(0.84))
                .background(activeTool == tool ? Color.purple.opacity(0.42) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Brush")
    }

    private var toolActions: [ChartToolAction] {
        [
            ChartToolAction(icon: "line.diagonal", label: "Trend Line", drawingTool: .trendLine),
            ChartToolAction(icon: "chart.bar", label: "Volume", command: .toggleVolume),
            ChartToolAction(icon: "slider.vertical.3", textIcon: "VP", label: "VWAP", command: .toggleIndicators),
            ChartToolAction(icon: "rectangle", label: "Rectangle", drawingTool: .rectangle),
            ChartToolAction(icon: "line.horizontal.3", label: "Horizontal Line", drawingTool: .horizontalLine),
            ChartToolAction(icon: "square.fill", textIcon: "L", label: "Long Position", drawingTool: .longPosition, color: .green),
            ChartToolAction(icon: "square.fill", textIcon: "S", label: "Short Position", drawingTool: .shortPosition, color: .red),
            ChartToolAction(icon: "dollarsign.circle", label: "Paper Trade", drawingTool: .paperTrade),
            ChartToolAction(icon: "arrow.uturn.backward", label: "Undo", command: .undo),
            ChartToolAction(icon: "eraser", label: "Eraser", drawingTool: .eraser),
            ChartToolAction(icon: "ruler", label: "Measure", drawingTool: .measure),
            ChartToolAction(icon: "line.diagonal.arrow", label: "Ray", drawingTool: .ray),
            ChartToolAction(icon: "fib", label: "Fib Retracement", drawingTool: .fibRetracement)
        ]
    }

    private var paperTradeToolAction: ChartToolAction {
        ChartToolAction(icon: "dollarsign.circle", label: "Paper Trade", drawingTool: .paperTrade)
    }

    @ViewBuilder
    private func toolActionIcon(_ action: ChartToolAction) -> some View {
        Group {
            if action.label == "VWAP", let textIcon = action.textIcon {
                VStack(spacing: 1) {
                    Text(textIcon)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: CGPoint(x: 2, y: size.height * 0.5))
                        path.addCurve(
                            to: CGPoint(x: size.width - 2, y: size.height * 0.5),
                            control1: CGPoint(x: size.width * 0.32, y: 0),
                            control2: CGPoint(x: size.width * 0.68, y: size.height)
                        )
                        context.stroke(path, with: .color(.white.opacity(0.88)), lineWidth: 1.4)
                    }
                    .frame(width: 18, height: 5)
                }
            } else if let textIcon = action.textIcon {
                Text(textIcon)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(action.color == nil ? .white.opacity(0.88) : .black.opacity(0.88))
                    .frame(width: 24, height: 24)
                    .background((action.color ?? .clear).opacity(action.color == nil ? 0 : 0.94), in: RoundedRectangle(cornerRadius: 5))
            } else if action.label == "Fib Retracement" {
                Canvas { context, size in
                    let color = (action.color ?? .white).opacity(0.9)
                    let ys = [5.5, 11.5, 17.5, 23.5].map { CGFloat($0) }
                    for (index, y) in ys.enumerated() {
                        var line = Path()
                        line.move(to: CGPoint(x: 8, y: y))
                        line.addLine(to: CGPoint(x: size.width - 8, y: y))
                        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))

                        if index == 1 {
                            context.fill(Path(ellipseIn: CGRect(x: 5, y: y - 3, width: 6, height: 6)), with: .color(color))
                        } else if index == 3 {
                            context.fill(Path(ellipseIn: CGRect(x: size.width - 11, y: y - 3, width: 6, height: 6)), with: .color(color))
                        }
                    }
                }
            } else if action.label == "Ray" {
                Canvas { context, size in
                    let start = CGPoint(x: 9, y: size.height - 6)
                    let anchor = CGPoint(x: 23, y: 14)
                    let tip = CGPoint(x: size.width - 8, y: 5)
                    var line = Path()
                    line.move(to: start)
                    line.addLine(to: tip)
                    context.stroke(line, with: .color((action.color ?? .white).opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    var head = Path()
                    head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - 8, y: tip.y + 1))
                    head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - 2, y: tip.y + 8))
                    context.stroke(head, with: .color((action.color ?? .white).opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    for point in [start, anchor] {
                        let dot = CGRect(x: point.x - 3.2, y: point.y - 3.2, width: 6.4, height: 6.4)
                        context.fill(Path(ellipseIn: dot), with: .color(.black.opacity(0.72)))
                        context.stroke(Path(ellipseIn: dot), with: .color((action.color ?? .white).opacity(0.95)), lineWidth: 1.7)
                    }
                }
            } else {
                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .medium))
            }
        }
        .frame(width: 44, height: 28)
        .foregroundStyle((action.color ?? .white).opacity(0.88))
        .background(toolIsActive(action) ? Color.purple.opacity(0.42) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private func handleToolAction(_ action: ChartToolAction) {
        if let drawingTool = action.drawingTool {
            activeTool = activeTool == drawingTool ? nil : drawingTool
            return
        }

        switch action.command {
        case .toggleVolume:
            showVolume.toggle()
        case .toggleIndicators:
            showIndicators.toggle()
        case .undo:
            undoLastDrawingStep()
        case .toggleReplay:
            toggleReplaySelection()
        case .eraseDrawings:
            recordDrawingHistory()
            drawings.removeAll()
            activeTool = nil
        case .none:
            break
        }
    }

    private func recordDrawingHistory() {
        guard drawingHistory.last != drawings else { return }
        drawingHistory.append(drawings)
        if drawingHistory.count > 80 {
            drawingHistory.removeFirst(drawingHistory.count - 80)
        }
    }

    private func undoLastDrawingStep() {
        guard let previous = drawingHistory.popLast() else { return }
        drawings = previous
        activeTool = nil
    }

    private func toolIsActive(_ action: ChartToolAction) -> Bool {
        if let drawingTool = action.drawingTool {
            return activeTool == drawingTool
        }
        if action.command == .toggleVolume {
            return showVolume
        }
        if action.command == .toggleIndicators {
            return showIndicators
        }
        if action.command == .toggleReplay {
            return isReplayMode || isAwaitingReplayStart
        }
        return false
    }

    private var replayPlaybackID: String {
        "\(isReplayPlaying)-\(replaySpeed.rawValue)-\(replayUpdateInterval.rawValue)-\(store.candles.count)"
    }

    private func toggleReplaySelection() {
        if isReplayMode || isAwaitingReplayStart {
            exitReplay()
        } else {
            activeTool = nil
            isReplayPlaying = false
            isAwaitingReplayStart = true
            isReplayMode = false
            replayStartIndex = nil
            replayCurrentIndex = nil
            replayCandleProgress = 1
        }
    }

    private func exitReplay() {
        isReplayPlaying = false
        isReplayMode = false
        isAwaitingReplayStart = false
        replayStartIndex = nil
        replayCurrentIndex = nil
        replayCandleProgress = 1
    }

    private func clampReplayToLoadedCandles() {
        guard isReplayMode || isAwaitingReplayStart else { return }

        guard !store.candles.isEmpty else {
            isReplayPlaying = false
            isReplayMode = false
            isAwaitingReplayStart = true
            replayStartIndex = nil
            replayCurrentIndex = nil
            replayCandleProgress = 1
            return
        }

        let lastIndex = store.candles.count - 1
        if let replayStartIndex {
            self.replayStartIndex = min(max(replayStartIndex, 0), lastIndex)
        }
        if let replayCurrentIndex {
            self.replayCurrentIndex = min(max(replayCurrentIndex, 0), lastIndex)
        }
        replayCandleProgress = 1
    }

    private func stepReplayForward() {
        guard isReplayMode, let current = replayCurrentIndex else { return }
        guard current < store.candles.count - 1 else {
            isReplayPlaying = false
            return
        }
        let next = min(current + replayUpdateInterval.rawValue, store.candles.count - 1)
        replayCurrentIndex = next
        replayCandleProgress = 1
        if next == store.candles.count - 1 {
            isReplayPlaying = false
        }
    }

    private func stepReplayBack() {
        guard isReplayMode, let current = replayCurrentIndex else { return }
        let lowerBound = replayStartIndex ?? 0
        replayCurrentIndex = max(lowerBound, current - replayUpdateInterval.rawValue)
        replayCandleProgress = 1
        isReplayPlaying = false
    }

    private func toggleReplayPlayback() {
        guard isReplayMode, let current = replayCurrentIndex else { return }
        isReplayPlaying = current < store.candles.count - 1 ? !isReplayPlaying : false
    }

    @MainActor
    private func runReplayPlayback() async {
        guard isReplayPlaying else { return }
        while !Task.isCancelled, isReplayPlaying {
            for _ in 0..<replayUpdateInterval.rawValue {
                guard !Task.isCancelled, isReplayPlaying else { break }
                guard let current = replayCurrentIndex, current < store.candles.count - 1 else {
                    isReplayPlaying = false
                    break
                }

                replayCurrentIndex = current + 1
                replayCandleProgress = 0

                let frames = 12
                for frame in 1...frames {
                    try? await Task.sleep(for: replaySpeed.interval / frames)
                    guard !Task.isCancelled, isReplayPlaying else { break }
                    replayCandleProgress = Double(frame) / Double(frames)
                }

                if replayCurrentIndex == store.candles.count - 1 {
                    isReplayPlaying = false
                    break
                }
            }
        }
    }

    private var symbolControlBar: some View {
        HStack(spacing: 22) {
            Text(store.selected.ticker)
                .font(.system(size: 25, weight: .heavy))
            Menu {
                ForEach(CandleInterval.allCases) { interval in
                    Button {
                        Task {
                            await store.selectInterval(interval)
                        }
                    } label: {
                        HStack {
                            Text(interval.rawValue)
                            if interval == store.selectedInterval {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(store.selectedInterval.rawValue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.bold())
                }
                .font(.system(size: 25, weight: .heavy))
            }
            Spacer()
            styleButton(.candles, icon: "pencil.and.scribble")
            styleButton(.line, icon: "waveform.path.ecg")
            styleButton(.area, icon: "chart.line.uptrend.xyaxis")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.94))
    }

    private func styleButton(_ style: ChartStyle, icon: String) -> some View {
        Button {
            chartStyle = style
        } label: {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 42, height: 38)
                .background(chartStyle == style ? Color.white.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private enum DrawingTool: String, Equatable {
    case crosshair
    case trendLine
    case brush
    case rectangle
    case horizontalLine
    case measure
    case ray
    case fibRetracement
    case longPosition
    case shortPosition
    case paperTrade
    case eraser
}

private enum ToolRailOrientation {
    case vertical
    case horizontal
}

private struct ChartSurfaceLayout {
    let topInset: CGFloat
    let chartHeight: CGFloat
    let volumeHeight: CGFloat
    let dateAxisHeight: CGFloat
    let bottomInset: CGFloat
    let dateAxisFontSize: CGFloat

    var volumeTop: CGFloat {
        topInset + chartHeight
    }

    var dateAxisMidY: CGFloat {
        volumeTop + volumeHeight + dateAxisHeight / 2
    }
}

private enum ChartToolCommand: Equatable {
    case toggleVolume
    case toggleIndicators
    case toggleReplay
    case undo
    case eraseDrawings
}

private enum ReplaySpeed: String, CaseIterable, Identifiable {
    case quarter = "0.25x"
    case half = "0.5x"
    case one = "1x"
    case two = "2x"
    case five = "5x"
    case ten = "10x"

    var id: String { rawValue }

    var interval: Duration {
        switch self {
        case .quarter:
            return .milliseconds(3_400)
        case .half:
            return .milliseconds(1_700)
        case .one:
            return .milliseconds(850)
        case .two:
            return .milliseconds(430)
        case .five:
            return .milliseconds(170)
        case .ten:
            return .milliseconds(85)
        }
    }
}

private enum ReplayUpdateInterval: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case five = 5
    case ten = 10
    case twentyFive = 25

    var id: Int { rawValue }

    var label: String {
        rawValue == 1 ? "1 Update" : "\(rawValue) Updates"
    }
}

private struct ChartToolAction: Identifiable {
    let icon: String
    var textIcon: String?
    let label: String
    var drawingTool: DrawingTool?
    var command: ChartToolCommand?
    var color: Color?

    var id: String { label }
}

private struct ChartCoordinate: Equatable {
    let barIndex: Double
    let price: Double
}

private struct VWAPPoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
    let upperBand: Double
    let lowerBand: Double
}

private struct ChartDrawing: Identifiable, Equatable {
    let id = UUID()
    let tool: DrawingTool
    var points: [ChartCoordinate]
}

private enum ReplayTradeOutcome {
    case target(Double)
    case stop(Double)
}

private enum PositionDragHandle {
    case move
    case entry
    case target
    case stop
    case duration
    case positionTargetLeft
    case positionTargetRight
    case positionStopLeft
    case positionStopRight
    case positionEntryLeft
    case positionEntryRight
    case rayOrigin
    case rayDirection
    case rayMove
    case measureStart
    case measureEnd
    case measureMove
    case rectangleTopLeft
    case rectangleTopRight
    case rectangleBottomLeft
    case rectangleBottomRight
    case rectangleMove
    case lineStart
    case lineEnd
    case lineMove
    case fibStart
    case fibEnd
    case fibMove
}

private struct PositionDragState {
    let drawingID: UUID
    let handle: PositionDragHandle
    let startPoint: ChartCoordinate
    let originalDrawing: ChartDrawing
}

private enum PaperOrderDragHandle {
    case entry
    case stop
    case target
    case cancel
}

private struct PaperOrderDragState {
    let orderID: UUID
    let handle: PaperOrderDragHandle
}

private struct ChartGestureOverlay: UIViewRepresentable {
    let onPanChanged: (CGPoint, CGPoint, CGPoint, CGSize) -> Void
    let onPanEnded: (CGPoint, CGPoint, CGPoint, CGSize) -> Void
    let onPinchChanged: (CGFloat) -> Void
    let onPinchEnded: () -> Void
    let onLongPressChanged: (CGPoint, CGSize) -> Void
    let onTap: (CGPoint, CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.allowableMovement = 12
        longPress.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator

        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ChartGestureOverlay
        private var panStart = CGPoint.zero

        init(_ parent: ChartGestureOverlay) {
            self.parent = parent
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            let translation = recognizer.translation(in: view)
            let size = view.bounds.size

            switch recognizer.state {
            case .began:
                panStart = location
                parent.onPanChanged(location, panStart, translation, size)
            case .changed:
                parent.onPanChanged(location, panStart, translation, size)
            case .ended, .cancelled, .failed:
                parent.onPanEnded(location, panStart, translation, size)
            default:
                break
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                parent.onPinchChanged(recognizer.scale)
            case .ended, .cancelled, .failed:
                parent.onPinchEnded()
            default:
                break
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            switch recognizer.state {
            case .began, .changed:
                parent.onLongPressChanged(recognizer.location(in: view), view.bounds.size)
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            guard recognizer.state == .ended else { return }
            parent.onTap(recognizer.location(in: view), view.bounds.size)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct TradingChartCanvas: View {
    let symbol: MarketSymbol
    @Bindable var paperTrading: PaperTradingService
    let candles: [Candle]
    let style: ChartStyle
    let showIndicators: Bool
    let showVolume: Bool
    let interval: CandleInterval
    let backgroundTheme: ChartBackgroundTheme
    let isLoading: Bool
    let errorMessage: String?
    @Binding var activeTool: DrawingTool?
    @Binding var drawings: [ChartDrawing]
    @Binding var isReplayMode: Bool
    @Binding var isAwaitingReplayStart: Bool
    @Binding var isChoosingReplayStartMethod: Bool
    @Binding var replayStartIndex: Int?
    @Binding var replayCurrentIndex: Int?
    @Binding var replaySpeed: ReplaySpeed
    @Binding var replayUpdateInterval: ReplayUpdateInterval
    @Binding var isReplayPlaying: Bool
    @Binding var replayCandleProgress: Double
    @Binding var lastVisibleCandle: Candle?
    let recordDrawingHistory: () -> Void
    let notifyOrderPlacedOnCurrentPrice: () -> Void

    @State private var visibleCount = 120
    @State private var baseVisibleCount = 120
    @State private var endIndex: Int?
    @State private var baseEndIndex: Int?
    @State private var draftDrawing: ChartDrawing?
    @State private var longPressStartLocation: CGPoint?
    @State private var longPressWorkItem: DispatchWorkItem?
    @State private var crosshairLocation: CGPoint?
    @State private var crosshairCandle: Candle?
    @State private var crosshairActivatedDuringGesture = false
    @State private var showSpookyiky = false
    @State private var positionDragState: PositionDragState?
    @State private var pendingRayStart: ChartCoordinate?
    @State private var pendingFibStart: ChartCoordinate?
    @State private var selectedDrawingID: UUID?
    @State private var selectedPaperOrderID: UUID?
    @State private var paperOrderDragState: PaperOrderDragState?
    @State private var replayBarOffset: CGSize = .zero
    @State private var replayBarDragStart: CGSize?
    @State private var didDragReplayBar = false
    @State private var liveMarkerClock = Date()

    var closes: [Double] {
        visibleCandles.map(\.close)
    }

    var renderCandles: [Candle] {
        guard isReplayMode, let replayCurrentIndex else { return candles }
        guard !candles.isEmpty else { return [] }
        let end = min(max(replayCurrentIndex, 0), candles.count - 1)
        return Array(candles[0...end])
    }

    var visibleCandles: [Candle] {
        guard !renderCandles.isEmpty else { return [] }
        let viewportStart = viewportStartIndex
        let end = min(clampedEndIndex, renderCandles.count - 1)
        let start = min(max(0, viewportStart), end)
        var visible = Array(renderCandles[start...end])
        if let last = visible.indices.last,
           isReplayMode,
           renderCandles[end].index == replayCurrentIndex,
           replayCandleProgress < 1 {
            visible[last] = formingCandle(from: visible[last], progress: replayCandleProgress)
        }
        return visible
    }

    private func formingCandle(from candle: Candle, progress: Double) -> Candle {
        let progress = min(max(progress, 0), 1)
        let close = candle.open + (candle.close - candle.open) * progress
        let high = max(candle.open, close, candle.open + (candle.high - candle.open) * progress)
        let low = min(candle.open, close, candle.open + (candle.low - candle.open) * progress)
        return Candle(
            index: candle.index,
            date: candle.date,
            open: candle.open,
            high: high,
            low: low,
            close: close,
            volume: candle.volume * progress
        )
    }

    var clampedVisibleCount: Int {
        guard !renderCandles.isEmpty else { return visibleCount }
        return min(max(visibleCount, 24), renderCandles.count)
    }

    var clampedEndIndex: Int {
        guard !renderCandles.isEmpty else { return 0 }
        return min(max(endIndex ?? renderCandles.count - 1, minimumEndIndex), maximumEndIndex)
    }

    private var minimumEndIndex: Int {
        min(clampedVisibleCount - 1, max(renderCandles.count - 1, 0))
    }

    private var maximumEndIndex: Int {
        let latest = max(renderCandles.count - 1, 0)
        return latest + futureScrollBars
    }

    private var futureScrollBars: Int {
        max(12, Int(Double(clampedVisibleCount) * 0.78))
    }

    private var viewportStartIndex: Int {
        max(0, clampedEndIndex - clampedVisibleCount + 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = chartLayout(in: proxy.size)
            ZStack {
            LinearGradient(
                colors: backgroundTheme.colors,
                startPoint: .top,
                endPoint: .bottom
            )

            gridLines

            VStack(spacing: 0) {
                Spacer(minLength: layout.topInset)
                chart
                    .frame(height: layout.chartHeight)
                    .padding(.leading, 6)
                    .padding(.trailing, 54)
                if showVolume {
                    volumeChart
                        .frame(height: layout.volumeHeight)
                        .padding(.leading, 8)
                        .padding(.trailing, 54)
                }
                dateAxisLabels
                    .font(.system(size: layout.dateAxisFontSize, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.dateAxisHeight, alignment: .center)
                    .padding(.leading, 8)
                    .padding(.trailing, 84)
                Spacer(minLength: layout.bottomInset)
            }

            priceAxis(size: proxy.size)

            drawingOverlay(size: proxy.size)
            paperTradingOverlay(size: proxy.size)
            paperOrderEditor(size: proxy.size)
            longPressCrosshair(size: proxy.size)

            chartStatusOverlay
            ChartGestureOverlay(
                onPanChanged: { location, startLocation, translation, size in
                    handleGesturePanChanged(location: location, startLocation: startLocation, translation: translation, size: size)
                },
                onPanEnded: { location, startLocation, translation, size in
                    handleGesturePanEnded(location: location, startLocation: startLocation, translation: translation, size: size)
                },
                onPinchChanged: { scale in
                    handlePinchChanged(scale)
                },
                onPinchEnded: {
                    handlePinchEnded()
                },
                onLongPressChanged: { location, _ in
                    guard !renderCandles.isEmpty else { return }
                    baseEndIndex = nil
                    updateCrosshair(at: location, in: proxy.size)
                    crosshairActivatedDuringGesture = true
                },
                onTap: { location, size in
                    if isAwaitingReplayStart && !isChoosingReplayStartMethod {
                        selectReplayStart(at: location, in: size)
                    } else if activeTool == .eraser {
                        removeDrawing(at: location, in: size)
                    } else if activeTool == .longPosition || activeTool == .shortPosition {
                        placePositionDrawing(at: location, in: size)
                    } else if activeTool == .ray {
                        placeRayPoint(at: location, in: size)
                    } else if activeTool == .fibRetracement {
                        placeFibPoint(at: location, in: size)
                    } else if crosshairLocation != nil {
                        clearLongPressCrosshair()
                    } else if selectPaperOrder(at: location, in: size) {
                        activeTool = nil
                    } else {
                        selectEditableDrawing(at: location, in: size)
                    }
                }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)

            spookySignature
        }
        .onChange(of: candles.count) { oldCount, newCount in
            guard newCount > 0 else { return }
            let wasFollowingLeadingEdge = endIndex == nil || clampedEndIndex >= max(oldCount - 1, 0)
            if oldCount <= 0 {
                resetViewport(candleCount: newCount)
            } else if wasFollowingLeadingEdge, !isReplayMode {
                endIndex = newCount - 1
                baseEndIndex = nil
            } else {
                endIndex = min(max(endIndex ?? clampedEndIndex, minimumEndIndex), maximumEndIndex)
                baseEndIndex = nil
            }
            updateLastVisibleCandle()
        }
        .onChange(of: interval) { _, _ in
            guard !renderCandles.isEmpty else { return }
            resetViewport(candleCount: candles.count)
            updateLastVisibleCandle()
        }
        .onChange(of: activeTool) { _, newTool in
            selectedDrawingID = nil
            selectedPaperOrderID = nil
            if newTool != .ray {
                pendingRayStart = nil
            }
            if newTool != .fibRetracement {
                pendingFibStart = nil
            }
        }
        .onChange(of: replayCurrentIndex) { oldValue, newValue in
            guard isReplayMode, !renderCandles.isEmpty else { return }
            let oldReplayIndex = oldValue ?? newValue ?? 0
            let newReplayIndex = newValue ?? oldReplayIndex
            let delta = max(0, newReplayIndex - oldReplayIndex)
            if let currentEndIndex = endIndex {
                if currentEndIndex >= oldReplayIndex {
                    endIndex = min(currentEndIndex + delta, maximumEndIndex)
                }
            } else {
                endIndex = renderCandles.count - 1
            }
            baseEndIndex = nil
            updateLastVisibleCandle()
        }
        .onChange(of: isReplayMode) { _, isActive in
            if isActive {
                isChoosingReplayStartMethod = false
                replayBarOffset = .zero
                replayBarDragStart = nil
            }
            resetViewport(candleCount: isActive ? renderCandles.count : candles.count)
            updateLastVisibleCandle()
        }
        .onAppear {
            updateLastVisibleCandle()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                liveMarkerClock = Date()
            }
        }
        }
    }

    private var gridLines: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                let rect = plotRect(in: proxy.size)

                for step in 1..<10 {
                    let y = height * CGFloat(step) / 10
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }

                for index in verticalGridIndexes {
                    let x = xPosition(for: Double(index), in: rect)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
            }
            .stroke(backgroundTheme.gridColor, lineWidth: 1)
        }
    }

    private var chart: some View {
        Chart {
            switch style {
            case .candles:
                ForEach(visibleCandles) { candle in
                    let candleColor = candle.close >= candle.open ? Color.green : Color.red

                    RectangleMark(
                        x: .value("Bar", candle.index),
                        yStart: .value("Low", candle.low),
                        yEnd: .value("High", candle.high),
                        width: .fixed(wickWidth)
                    )
                    .foregroundStyle(candleColor)

                    RectangleMark(
                        x: .value("Bar", candle.index),
                        yStart: .value("Open", min(candle.open, candle.close)),
                        yEnd: .value("Close", max(candle.open, candle.close)),
                        width: .fixed(candleBodyWidth)
                    )
                    .foregroundStyle(candleColor)
                }
            case .line:
                ForEach(visibleCandles) { candle in
                    LineMark(x: .value("Bar", candle.index), y: .value("Close", candle.close))
                        .foregroundStyle(backgroundTheme.markColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.3))
                }
            case .area:
                ForEach(visibleCandles) { candle in
                    AreaMark(x: .value("Bar", candle.index), y: .value("Close", candle.close))
                        .foregroundStyle(backgroundTheme.markColor.opacity(0.18))
                    LineMark(x: .value("Bar", candle.index), y: .value("Close", candle.close))
                        .foregroundStyle(backgroundTheme.markColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.3))
                }
            }

            if showIndicators {
                ForEach(vwapPoints) { point in
                    LineMark(x: .value("Bar", point.index), y: .value("VWAP", point.value))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2.0))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
    }

    private var volumeChart: some View {
        Chart(visibleCandles) { candle in
            BarMark(
                x: .value("Bar", candle.index),
                y: .value("Volume", candle.volume),
                width: .fixed(volumeBarWidth)
            )
            .foregroundStyle(candle.close >= candle.open ? .cyan.opacity(0.75) : .red.opacity(0.55))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: xDomain)
    }

    private var spookySignature: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 8) {
                Text("S")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.black)
                    .contentShape(Rectangle())
                    .onLongPressGesture(
                        minimumDuration: 0.2,
                        maximumDistance: 40,
                        pressing: { isPressing in
                            showSpookyiky = isPressing
                        },
                        perform: {}
                    )

                if showSpookyiky {
                    Text("Spookyiky")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.bottom, 9)
                        .transition(.opacity)
                }
            }
            .padding(.leading, 8)
            .padding(.bottom, 126)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var legacySignature: some View {
        Group {
            Text("S")
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(.black)
                .padding(.leading, 8)
                .padding(.bottom, 8)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let lows = visibleCandles.map(\.low)
        let highs = visibleCandles.map(\.high)
        let minValue = lows.min() ?? 0
        let maxValue = highs.max() ?? 1
        let padding = (maxValue - minValue) * 0.18
        return (minValue - padding)...(maxValue + padding)
    }

    private var priceTicks: [Double] {
        guard !visibleCandles.isEmpty else { return [] }
        let lower = yDomain.lowerBound
        let upper = yDomain.upperBound
        let range = upper - lower
        guard range > 0 else { return [lower] }

        let tickCount = 7
        return (0..<tickCount).map { index in
            upper - (range * Double(index) / Double(tickCount - 1))
        }
    }

    private var xDomain: ClosedRange<Int> {
        guard !renderCandles.isEmpty else {
            return 0...1
        }
        let latest = renderCandles.count - 1
        let isAtLatestCandle = clampedEndIndex == latest
        let liveOrReplayRightPadding = (isReplayMode || isAtLatestCandle) ? max(6, min(14, clampedVisibleCount / 8)) : 0
        let rightEdge = clampedEndIndex == latest ? latest + liveOrReplayRightPadding : clampedEndIndex
        return viewportStartIndex...max(viewportStartIndex + 1, rightEdge)
    }

    private var candleBodyWidth: CGFloat {
        let slotWidth = 820 / CGFloat(max(clampedVisibleCount, 1))
        return max(1.6, min(8.2, slotWidth * 0.58))
    }

    private var wickWidth: CGFloat {
        max(0.7, min(1.2, candleBodyWidth * 0.16))
    }

    private var volumeBarWidth: CGFloat {
        let slotWidth = 820 / CGFloat(max(clampedVisibleCount, 1))
        return max(0.45, min(7, slotWidth * 0.48))
    }

    private var dateAxisLabels: some View {
        HStack {
            ForEach(dateTicks, id: \.self) { label in
                Text(label)
                if label != dateTicks.last {
                    Spacer()
                }
            }
        }
    }

    private var dateTicks: [String] {
        guard !visibleCandles.isEmpty else { return ["--", "--", "--", "--"] }
        let labels = verticalGridIndexes.compactMap { gridIndex in
            visibleCandles.first(where: { $0.index == gridIndex })?.date
        }

        let dates = labels.isEmpty ? [
            visibleCandles.first?.date,
            visibleCandles.last?.date
        ].compactMap { $0 } : Array(labels.prefix(5))

        return dates.map { interval == .oneDay ? $0.shortChartLabel : $0.intradayChartLabel }
    }

    private func chartLayout(in size: CGSize) -> ChartSurfaceLayout {
        let isLandscape = size.width > size.height
        let minHeight = max(size.height, 1)

        guard isLandscape else {
            return ChartSurfaceLayout(
                topInset: 150,
                chartHeight: 470,
                volumeHeight: showVolume ? 96 : 0,
                dateAxisHeight: 18,
                bottomInset: 76,
                dateAxisFontSize: 11
            )
        }

        let topInset = max(72, min(104, minHeight * 0.22))
        let volumeHeight: CGFloat = showVolume ? max(32, min(54, minHeight * 0.13)) : 0
        let dateAxisHeight: CGFloat = 22
        let bottomInset: CGFloat = 8
        let availableChartHeight = minHeight - topInset - volumeHeight - dateAxisHeight - bottomInset
        let minimumChartHeight: CGFloat = 110
        let chartHeight = max(minimumChartHeight, availableChartHeight)
        let adjustedTopInset = max(52, min(topInset, minHeight - chartHeight - volumeHeight - dateAxisHeight - bottomInset))

        return ChartSurfaceLayout(
            topInset: adjustedTopInset,
            chartHeight: chartHeight,
            volumeHeight: volumeHeight,
            dateAxisHeight: dateAxisHeight,
            bottomInset: bottomInset,
            dateAxisFontSize: 9
        )
    }

    private func priceAxis(size: CGSize) -> some View {
        let rect = plotRect(in: size)
        return ZStack(alignment: .topTrailing) {
            ForEach(Array(priceTicks.enumerated()), id: \.offset) { _, price in
                Text(axisPriceLabel(for: price))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(backgroundTheme.markColor.opacity(0.88))
                    .frame(width: 52, alignment: .trailing)
                    .padding(.trailing, 4)
                    .position(
                        x: size.width - 28,
                        y: yPosition(for: price, in: rect)
                    )
            }

            if let candle = livePriceMarkerCandle {
                let rawY = yPosition(for: candle.close, in: rect)
                let y = min(max(rawY, rect.minY + 18), rect.maxY - 18)
                let markerColor = candle.close >= candle.open ? Color.green : Color.red

                Path { path in
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: min(size.width - 72, rect.maxX + 12), y: y))
                }
                .stroke(
                    markerColor.opacity(0.88),
                    style: StrokeStyle(lineWidth: 1.3, dash: [2.2, 4.0])
                )

                livePriceMarker(for: candle, color: markerColor)
                    .position(x: size.width - 73, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    private var livePriceMarkerCandle: Candle? {
        if isReplayMode {
            return visibleCandles.last ?? renderCandles.last
        }
        return renderCandles.last
    }

    private func livePriceMarker(for candle: Candle, color: Color) -> some View {
        HStack(spacing: 0) {
            Text(symbol.ticker)
                .font(.system(size: 12, weight: .black).monospacedDigit())
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.horizontal, 6)
                .frame(width: 58, height: 34)
                .background(.white)

            VStack(alignment: .leading, spacing: 0) {
                Text(axisPriceLabel(for: candle.close))
                    .font(.system(size: 12, weight: .black).monospacedDigit())
                    .lineLimit(1)
                Text(livePriceMarkerTimeLabel(for: candle))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .frame(width: 66, height: 34, alignment: .leading)
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(color.opacity(0.9), lineWidth: 1.4)
        )
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private func livePriceMarkerTimeLabel(for candle: Candle) -> String {
        if isReplayMode {
            return interval == .oneDay ? candle.date.shortChartLabel : candle.date.intradayChartLabel
        }

        guard interval != .oneDay else {
            return candle.date.intradayChartLabel
        }

        let elapsed = liveMarkerClock.timeIntervalSince(candle.date)
        let remaining = max(0, interval.seconds - elapsed.truncatingRemainder(dividingBy: interval.seconds))
        let totalSeconds = Int(ceil(remaining))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var chartStatusOverlay: some View {
        Group {
            if isLoading {
                ProgressView("Loading real market data")
                    .font(.headline)
                    .tint(.white)
                    .foregroundStyle(backgroundTheme.markColor)
                    .padding()
            } else if let errorMessage, candles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                    Text("Market Data Unavailable")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(backgroundTheme.markColor.opacity(0.72))
                }
                .foregroundStyle(backgroundTheme.markColor)
                .padding()
                .frame(maxWidth: 280)
            }
        }
    }

    private func replayOverlay(size: CGSize) -> some View {
        replayControlBar(size: size)
            .position(replayBarPosition(in: size))
            .gesture(replayBarDragGesture(in: size))
            .frame(width: size.width, height: size.height)
        .animation(.spring(response: 0.32, dampingFraction: 0.74), value: isAwaitingReplayStart)
        .animation(.spring(response: 0.32, dampingFraction: 0.74), value: isReplayMode)
    }

    private func replayBarPosition(in size: CGSize) -> CGPoint {
        let base = replayBarBasePosition(in: size)
        let halfWidth = replayControlWidth(in: size) / 2
        let rightClearance = replayRightClearance(in: size)
        return CGPoint(
            x: min(max(base.x + replayBarOffset.width, halfWidth + 8), size.width - halfWidth - rightClearance),
            y: min(max(base.y + replayBarOffset.height, 96), replayBarMaxY(in: size))
        )
    }

    private func replayBarBasePosition(in size: CGSize) -> CGPoint {
        let width = replayControlWidth(in: size)
        return CGPoint(x: size.width - replayRightClearance(in: size) - width / 2, y: max(120, replayBarMaxY(in: size)))
    }

    private func replayControlWidth(in size: CGSize) -> CGFloat {
        let maxWidth = max(52, size.width - replayRightClearance(in: size) - 16)
        return replayIsActive ? min(maxWidth, isChoosingReplayStartMethod ? 318 : 372) : 52
    }

    private func replayRightClearance(in size: CGSize) -> CGFloat {
        8
    }

    private func replayBarMaxY(in size: CGSize) -> CGFloat {
        let compactBottomClearance: CGFloat = size.height > size.width ? 22 : 92
        return size.height - compactBottomClearance
    }

    private func replayBarDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if replayBarDragStart == nil {
                    replayBarDragStart = replayBarOffset
                }

                let start = replayBarDragStart ?? .zero
                let proposed = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                if hypot(value.translation.width, value.translation.height) > 4 {
                    didDragReplayBar = true
                }
                replayBarOffset = clampedReplayBarOffset(proposed, in: size)
            }
            .onEnded { _ in
                replayBarDragStart = nil
                DispatchQueue.main.async {
                    didDragReplayBar = false
                }
            }
    }

    private func clampedReplayBarOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        let base = replayBarBasePosition(in: size)
        let halfWidth = replayControlWidth(in: size) / 2
        let rightClearance = replayRightClearance(in: size)
        let minX = halfWidth + 8
        let maxX = size.width - halfWidth - rightClearance
        let minY: CGFloat = 96
        let maxY = replayBarMaxY(in: size)
        let clampedX = min(max(base.x + offset.width, minX), maxX)
        let clampedY = min(max(base.y + offset.height, minY), maxY)
        return CGSize(width: clampedX - base.x, height: clampedY - base.y)
    }

    private func replayControlBar(size: CGSize) -> some View {
        HStack(spacing: replayIsActive ? 8 : 0) {
            if replayIsActive {
                Text("Replay")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                if isChoosingReplayStartMethod {
                    HStack(spacing: 8) {
                        Button {
                            isChoosingReplayStartMethod = false
                            isAwaitingReplayStart = true
                            isReplayMode = false
                            isReplayPlaying = false
                            replayStartIndex = nil
                            replayCurrentIndex = nil
                            replayCandleProgress = 1
                        } label: {
                            Text("Tap to choose start")
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.74)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        }

                        Button {
                            selectRandomReplayStart()
                        } label: {
                            Text("Random")
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(isAwaitingReplayStart ? "Tap candle" : replayTimeLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                }

                if isReplayMode && !isChoosingReplayStartMethod {
                    Button {
                        stepReplayBack()
                    } label: {
                        Image(systemName: "backward.frame.fill")
                    }
                    .disabled(!canStepReplayBack)

                    Button {
                        isReplayPlaying.toggle()
                    } label: {
                        Image(systemName: isReplayPlaying ? "pause.fill" : "play.fill")
                    }
                    .disabled(!canStepReplayForward && !isReplayPlaying)

                    Button {
                        stepReplayForward()
                    } label: {
                        Image(systemName: "forward.frame.fill")
                    }
                    .disabled(!canStepReplayForward)

                    Menu {
                        ForEach(ReplaySpeed.allCases) { speed in
                            Button {
                                replaySpeed = speed
                            } label: {
                                HStack {
                                    Text(speed.rawValue)
                                    if replaySpeed == speed {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text("Speed")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white.opacity(0.62))
                            Text(replaySpeed.rawValue)
                                .font(.caption.bold().monospacedDigit())
                        }
                        .frame(minWidth: 40)
                    }

                    Menu {
                        ForEach(ReplayUpdateInterval.allCases) { interval in
                            Button {
                                replayUpdateInterval = interval
                            } label: {
                                HStack {
                                    Text(interval.label)
                                    if replayUpdateInterval == interval {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text("Updates")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white.opacity(0.62))
                            Text("\(replayUpdateInterval.rawValue)")
                                .font(.caption.bold().monospacedDigit())
                        }
                        .frame(minWidth: 45)
                    }
                }

                Spacer(minLength: 0)
            }

            Image(systemName: "backward.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !didDragReplayBar else { return }
                    toggleReplayControl()
                }
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.leading, replayIsActive ? 12 : 8)
        .padding(.trailing, 8)
        .frame(width: replayControlWidth(in: size), alignment: .trailing)
        .frame(height: 36)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .clipped()
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: replayIsActive)
    }

    private var replayIsActive: Bool {
        isReplayMode || isAwaitingReplayStart
    }

    private func toggleReplayControl() {
        if replayIsActive {
            exitReplay()
        } else {
            activeTool = nil
            isReplayPlaying = false
            isAwaitingReplayStart = true
            isChoosingReplayStartMethod = true
            isReplayMode = false
            replayStartIndex = nil
            replayCurrentIndex = nil
            replayCandleProgress = 1
            replayBarDragStart = nil
        }
    }

    private var replayTimeLabel: String {
        guard let replayCurrentIndex, candles.indices.contains(replayCurrentIndex) else {
            return "--"
        }
        let date = candles[replayCurrentIndex].date
        return interval == .oneDay ? date.chartLabel : date.crosshairIntradayLabel
    }

    private var canStepReplayForward: Bool {
        guard isReplayMode, let replayCurrentIndex else { return false }
        return replayCurrentIndex < candles.count - 1
    }

    private var canStepReplayBack: Bool {
        guard isReplayMode, let replayCurrentIndex else { return false }
        return replayCurrentIndex > (replayStartIndex ?? 0)
    }

    private func selectReplayStart(at location: CGPoint, in size: CGSize) {
        guard !renderCandles.isEmpty else { return }
        let rect = plotRect(in: size)
        let point = screenToPoint(location, in: rect)
        let selected = candles.enumerated().min { first, second in
            abs(Double(first.element.index) - point.barIndex) < abs(Double(second.element.index) - point.barIndex)
        }?.offset ?? 0

        isReplayPlaying = false
        replayStartIndex = selected
        replayCurrentIndex = selected
        replayCandleProgress = 1
        isReplayMode = true
        isAwaitingReplayStart = false
        isChoosingReplayStartMethod = false
        activeTool = nil
        crosshairLocation = nil
        baseEndIndex = nil
        resetViewport(candleCount: selected + 1)
    }

    private func selectRandomReplayStart() {
        guard candles.count > 1 else { return }
        let lastDate = candles.last?.date ?? Date()
        let threshold = Calendar.current.date(byAdding: .year, value: -3, to: lastDate) ?? candles[0].date
        let lastSelectableIndex = max(0, candles.count - 2)
        let candidates = candles.enumerated()
            .filter { index, candle in
                index <= lastSelectableIndex && candle.date >= threshold
            }
            .map(\.offset)
        let selected = candidates.randomElement() ?? Int.random(in: 0...lastSelectableIndex)

        isReplayPlaying = false
        replayStartIndex = selected
        replayCurrentIndex = selected
        replayCandleProgress = 1
        isReplayMode = true
        isAwaitingReplayStart = false
        isChoosingReplayStartMethod = false
        activeTool = nil
        crosshairLocation = nil
        baseEndIndex = nil
        resetViewport(candleCount: selected + 1)
    }

    private func stepReplayForward() {
        guard canStepReplayForward, let current = replayCurrentIndex else {
            isReplayPlaying = false
            return
        }
        replayCurrentIndex = min(current + replayUpdateInterval.rawValue, candles.count - 1)
        replayCandleProgress = 1
        if replayCurrentIndex == candles.count - 1 {
            isReplayPlaying = false
        }
    }

    private func stepReplayBack() {
        guard canStepReplayBack, let current = replayCurrentIndex else {
            isReplayPlaying = false
            return
        }
        replayCurrentIndex = max(replayStartIndex ?? 0, current - replayUpdateInterval.rawValue)
        replayCandleProgress = 1
        isReplayPlaying = false
    }

    private func exitReplay() {
        isReplayPlaying = false
        isReplayMode = false
        isAwaitingReplayStart = false
        isChoosingReplayStartMethod = false
        replayStartIndex = nil
        replayCurrentIndex = nil
        replayCandleProgress = 1
        baseEndIndex = nil
        resetViewport(candleCount: candles.count)
    }

    private var interactionHint: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(activeTool == nil ? "\(visibleCandles.count) \(interval.rawValue) candles · \(interval.gridLabel)" : "\(activeToolName) active")
                    .font(.caption.bold())
                    .foregroundStyle(backgroundTheme.markColor.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .padding(.trailing, 62)
                    .padding(.bottom, 220)
            }
        }
        .opacity(candles.isEmpty ? 0 : 1)
    }

    private var activeToolName: String {
        switch activeTool {
        case .crosshair:
            return "Crosshair"
        case .trendLine:
            return "Trend line"
        case .brush:
            return "Brush"
        case .rectangle:
            return "Rectangle"
        case .horizontalLine:
            return "Horizontal"
        case .measure:
            return "Measure"
        case .ray:
            return "Ray"
        case .fibRetracement:
            return "Fib"
        case .longPosition:
            return "Long"
        case .shortPosition:
            return "Short"
        case .paperTrade:
            return "Paper trade"
        case .eraser:
            return "Eraser"
        case .none:
            return "Pan"
        }
    }

    private var fibLevels: [Double] {
        [-0.618, -0.236, 0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]
    }

    private func fibLevelLabel(_ level: Double) -> String {
        if abs(level - -0.618) < 0.0001 {
            return "-0.618 T2"
        }
        if abs(level - -0.236) < 0.0001 {
            return "-0.236 T1"
        }
        if level == 0 {
            return "0.0"
        }
        if level == 1 {
            return "1.0"
        }
        return String(format: "%.3f", level)
    }

    private func isFibBuyZoneLevel(_ level: Double) -> Bool {
        abs(level - 0.618) < 0.0001 || abs(level - 0.786) < 0.0001
    }

    private func drawingOverlay(size: CGSize) -> some View {
        let pendingRayDrawing = pendingRayStart.map { ChartDrawing(tool: .ray, points: [$0]) }
        let pendingFibDrawing = pendingFibStart.map { ChartDrawing(tool: .fibRetracement, points: [$0]) }
        let allDrawings = drawings + (draftDrawing.map { [$0] } ?? []) + (pendingRayDrawing.map { [$0] } ?? []) + (pendingFibDrawing.map { [$0] } ?? [])
        return Canvas { context, _ in
            let rect = plotRect(in: size)
            context.clip(to: Path(rect))

            for drawing in allDrawings {
                draw(drawing, in: rect, context: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private func paperTradingOverlay(size: CGSize) -> some View {
        Canvas { context, _ in
            let rect = plotRect(in: size)
            context.clip(to: Path(rect))

            let pendingOrders = paperTrading.account.pendingOrders.filter { paperObjectIsVisible(symbol: $0.symbol, isReplayTrade: $0.isReplayTrade) }
            for order in pendingOrders {
                drawOrderSetup(order, isSelected: selectedPaperOrderID == order.id, in: rect, context: &context)
            }

            let positions = paperTrading.account.openPositions.filter { paperObjectIsVisible(symbol: $0.symbol, isReplayTrade: $0.isReplayTrade) }
            for position in positions {
                drawTradeLine(
                    title: "\(position.direction.shortLabel) \(position.quantityText) \(position.unrealizedPL.signedMoneyText)",
                    price: position.entryPrice,
                    color: position.unrealizedPL >= 0 ? .green : .red,
                    style: StrokeStyle(lineWidth: 2.0),
                    in: rect,
                    context: &context
                )
                if let stopLoss = position.stopLoss {
                    drawTradeLine(title: "SL", price: stopLoss, color: .red, style: StrokeStyle(lineWidth: 1.3, dash: [4, 4]), in: rect, context: &context)
                }
                if let takeProfit = position.takeProfit {
                    drawTradeLine(title: "TP", price: takeProfit, color: .green, style: StrokeStyle(lineWidth: 1.3, dash: [4, 4]), in: rect, context: &context)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawOrderSetup(_ order: SimulatedOrder, isSelected: Bool, in rect: CGRect, context: inout GraphicsContext) {
        let color: Color = order.direction == .long ? .green : .red
        drawTradeLine(
            title: "\(order.direction == .long ? "Buy" : "Sell") \(order.quantityText)",
            price: order.entryPrice,
            color: color,
            style: StrokeStyle(lineWidth: isSelected ? 2.3 : 1.8),
            in: rect,
            context: &context
        )

        let y = yPosition(for: order.entryPrice, in: rect)
        if y >= rect.minY - 2, y <= rect.maxY + 2 {
            let pillX = rect.minX + min(210, rect.width * 0.36)
            let pill = CGRect(x: pillX - 100, y: y - 18, width: 200, height: 36)
            context.fill(Path(roundedRect: pill, cornerRadius: 10), with: .color(Color.white.opacity(0.94)))
            context.stroke(Path(roundedRect: pill, cornerRadius: 10), with: .color(color), lineWidth: 1.7)
            let mark = paperOrderMarkPrice()
            let estimatedPL = paperTrading.estimatedProfitLoss(for: order, markPrice: mark)
            let text = Text("\(order.direction == .long ? "Buy" : "Sell")  \(order.quantityText)   \(estimatedPL.signedMoneyText)   x")
                .font(.system(size: 12, weight: .black).monospacedDigit())
                .foregroundStyle(estimatedPL == 0 ? color : (estimatedPL > 0 ? Color.green : Color.red))
            context.draw(text, at: CGPoint(x: pill.midX, y: pill.midY))

            if paperOrderEntryIsEditable(order) {
                let dragDotX = rect.minX + rect.width * 0.64
                let dot = Path(ellipseIn: CGRect(x: dragDotX - 5, y: y - 5, width: 10, height: 10))
                context.fill(dot, with: .color(color))
                context.stroke(dot, with: .color(.white), lineWidth: 1.4)
            }
        }

        if let takeProfit = order.takeProfit {
            drawTradeLine(title: "TP", price: takeProfit, color: .mint, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]), in: rect, context: &context)
            drawOrderTag("TP", price: takeProfit, color: .mint, in: rect, context: &context)
        }
        if let stopLoss = order.stopLoss {
            drawTradeLine(title: "SL", price: stopLoss, color: .orange, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]), in: rect, context: &context)
            drawOrderTag("SL", price: stopLoss, color: .orange, in: rect, context: &context)
        }
    }

    private func drawOrderTag(_ title: String, price: Double, color: Color, in rect: CGRect, context: inout GraphicsContext) {
        let y = yPosition(for: price, in: rect)
        guard y >= rect.minY - 2, y <= rect.maxY + 2 else { return }
        let tag = CGRect(x: rect.minX + 90, y: y - 16, width: 48, height: 32)
        context.fill(Path(roundedRect: tag, cornerRadius: 9), with: .color(Color.white.opacity(0.92)))
        context.stroke(Path(roundedRect: tag, cornerRadius: 9), with: .color(color), lineWidth: 1.8)
        let label = Text(title)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(color)
        context.draw(label, at: CGPoint(x: tag.midX, y: tag.midY))
    }

    private func paperOrderEditor(size: CGSize) -> some View {
        EmptyView()
    }

    private var selectedPaperOrder: SimulatedOrder? {
        guard let selectedPaperOrderID else { return nil }
        return paperTrading.account.pendingOrders.first { $0.id == selectedPaperOrderID }
    }

    private func paperObjectIsVisible(symbol objectSymbol: String, isReplayTrade: Bool?) -> Bool {
        objectSymbol == symbol.ticker && (isReplayTrade == true) == isReplayMode
    }

    private func paperOrderMarkPrice() -> Double {
        visibleCandles.last?.close ?? renderCandles.last?.close ?? symbol.last
    }

    private func addTakeProfit(to order: SimulatedOrder) {
        let range = max(yDomain.upperBound - yDomain.lowerBound, 0.01)
        let price = order.takeProfit ?? (order.direction == .long ? order.entryPrice + range * 0.08 : order.entryPrice - range * 0.08)
        paperTrading.updatePendingOrder(order.id, takeProfit: price)
    }

    private func addStopLoss(to order: SimulatedOrder) {
        let range = max(yDomain.upperBound - yDomain.lowerBound, 0.01)
        let price = order.stopLoss ?? (order.direction == .long ? order.entryPrice - range * 0.05 : order.entryPrice + range * 0.05)
        paperTrading.updatePendingOrder(order.id, stopLoss: price)
    }

    private func drawTradeLine(title: String, price: Double, color: Color, style: StrokeStyle, in rect: CGRect, context: inout GraphicsContext) {
        let y = yPosition(for: price, in: rect)
        guard y >= rect.minY - 2, y <= rect.maxY + 2 else { return }

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        context.stroke(path, with: .color(color.opacity(0.9)), style: style)

        let label = Text("\(title) \(axisPriceLabel(for: price))")
            .font(.system(size: 10, weight: .black).monospacedDigit())
            .foregroundStyle(.white)
        let labelPoint = CGPoint(x: rect.maxX - 50, y: y - 10)
        let pill = Path(roundedRect: CGRect(x: labelPoint.x - 58, y: labelPoint.y - 10, width: 116, height: 20), cornerRadius: 5)
        context.fill(pill, with: .color(color.opacity(0.88)))
        context.draw(label, at: labelPoint)
    }

    private func longPressCrosshair(size: CGSize) -> some View {
        let layout = chartLayout(in: size)
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                guard let crosshairLocation else { return }

                var path = Path()
                path.move(to: CGPoint(x: 0, y: crosshairLocation.y))
                path.addLine(to: CGPoint(x: size.width, y: crosshairLocation.y))
                path.move(to: CGPoint(x: crosshairLocation.x, y: 0))
                path.addLine(to: CGPoint(x: crosshairLocation.x, y: size.height))

                context.stroke(
                    path,
                    with: .color(backgroundTheme.markColor.opacity(0.78)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 5])
                )

                let center = Path(ellipseIn: CGRect(x: crosshairLocation.x - 4, y: crosshairLocation.y - 4, width: 8, height: 8))
                context.fill(center, with: .color(backgroundTheme.markColor))
            }

            if let crosshairLocation, let crosshairCandle {
                Text(crosshairDateLabel(for: crosshairCandle.date))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black, in: RoundedRectangle(cornerRadius: 4))
                    .position(
                        x: min(max(crosshairLocation.x, 58), size.width - 58),
                        y: layout.dateAxisMidY
                    )

                Text(axisPriceLabel(for: price(atY: crosshairLocation.y, in: size)))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black, in: RoundedRectangle(cornerRadius: 4))
                    .position(
                        x: size.width - 31,
                        y: min(max(crosshairLocation.y, plotRect(in: size).minY + 12), plotRect(in: size).maxY - 12)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ drawing: ChartDrawing, in rect: CGRect, context: inout GraphicsContext) {
        guard let first = drawing.points.first else { return }
        let stroke = StrokeStyle(lineWidth: drawing.tool == .brush ? 2.5 : 2.2, lineCap: .round, lineJoin: .round)
        let primary = Color.black.opacity(0.92)
        let secondary = Color.white.opacity(0.88)
        let showEditHandles = drawing.id == selectedDrawingID || drawing.id == draftDrawing?.id

        func screenPoint(_ point: ChartCoordinate) -> CGPoint {
            pointToScreen(point, in: rect)
        }

        func drawHandle(at point: CGPoint, radius: CGFloat = 5) {
            let outer = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            let innerRadius = max(2.2, radius * 0.48)
            let inner = Path(ellipseIn: CGRect(x: point.x - innerRadius, y: point.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
            context.fill(outer, with: .color(backgroundTheme.isLight ? .white.opacity(0.92) : .black.opacity(0.72)))
            context.stroke(outer, with: .color(primary), lineWidth: 1.5)
            context.fill(inner, with: .color(primary))
        }

        switch drawing.tool {
        case .crosshair:
            let point = screenPoint(first)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: point.y))
            path.addLine(to: CGPoint(x: rect.maxX, y: point.y))
            path.move(to: CGPoint(x: point.x, y: rect.minY))
            path.addLine(to: CGPoint(x: point.x, y: rect.maxY))
            context.stroke(path, with: .color(secondary.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
        case .trendLine, .measure:
            guard let last = drawing.points.last else { return }
            var path = Path()
            let start = screenPoint(first)
            let end = screenPoint(last)
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(primary), style: stroke)

            if drawing.tool == .trendLine, showEditHandles {
                drawHandle(at: start)
                drawHandle(at: end)
            }

            if drawing.tool == .measure {
                let percent = first.price == 0 ? 0 : ((last.price - first.price) / first.price) * 100
                let bars = abs(last.barIndex - first.barIndex)
                let label = Text("\(percent.percentText)  \(String(format: "%.0f", bars)) bars")
                    .font(.caption.bold())
                    .foregroundStyle(backgroundTheme.isLight ? .black : .white)
                context.draw(label, at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 18))

                for point in [start, end] {
                    drawHandle(at: point)
                }
            }
        case .ray:
            guard let last = drawing.points.last else { return }
            let start = screenPoint(first)
            let end = screenPoint(last)
            let dx = abs(end.x - start.x) < 0.1 ? 1 : end.x - start.x
            let slope = (end.y - start.y) / dx
            var path = Path()
            path.move(to: start)
            path.addLine(to: CGPoint(x: rect.maxX, y: start.y + slope * (rect.maxX - start.x)))
            context.stroke(path, with: .color(primary), style: stroke)

            for point in [start, end] {
                let outer = Path(ellipseIn: CGRect(x: point.x - 5.5, y: point.y - 5.5, width: 11, height: 11))
                let inner = Path(ellipseIn: CGRect(x: point.x - 2.6, y: point.y - 2.6, width: 5.2, height: 5.2))
                context.fill(outer, with: .color(backgroundTheme.isLight ? .white.opacity(0.92) : .black.opacity(0.72)))
                context.stroke(outer, with: .color(primary), lineWidth: 1.6)
                context.fill(inner, with: .color(primary))
            }
        case .fibRetracement:
            guard let last = drawing.points.last else { return }
            let start = screenPoint(first)
            guard drawing.points.count >= 2 else {
                drawHandle(at: start, radius: 5.2)
                return
            }
            let end = screenPoint(last)
            var anchorPath = Path()
            anchorPath.move(to: start)
            anchorPath.addLine(to: end)
            context.stroke(anchorPath, with: .color(primary.opacity(0.52)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))

            let levels = fibLevels
            let priceDelta = last.price - first.price
            for level in levels {
                let price = first.price + priceDelta * level
                let y = yPosition(for: price, in: rect)
                guard y >= rect.minY - 1, y <= rect.maxY + 1 else { continue }
                var line = Path()
                line.move(to: CGPoint(x: rect.minX, y: y))
                line.addLine(to: CGPoint(x: rect.maxX, y: y))
                let lineColor = isFibBuyZoneLevel(level) ? Color.green.opacity(0.82) : primary.opacity(level == 0 || level == 1 ? 0.82 : 0.58)
                context.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: level == 0 || level == 1 ? 1.8 : 1.25))

                let label = Text("\(fibLevelLabel(level))  \(axisPriceLabel(for: price))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(backgroundTheme.isLight ? .black : .white)
                context.draw(label, at: CGPoint(x: rect.minX + 50, y: y - 10), anchor: .leading)
            }

            if showEditHandles {
                drawHandle(at: start, radius: 5.2)
                drawHandle(at: end, radius: 5.2)
            }
        case .rectangle:
            guard let last = drawing.points.last else { return }
            let start = screenPoint(first)
            let end = screenPoint(last)
            let drawRect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            let path = Path(roundedRect: drawRect, cornerRadius: 2)
            context.fill(path, with: .color(Color.purple.opacity(0.16)))
            context.stroke(path, with: .color(primary), lineWidth: 2)

            if showEditHandles {
                for point in [
                    CGPoint(x: drawRect.minX, y: drawRect.minY),
                    CGPoint(x: drawRect.maxX, y: drawRect.minY),
                    CGPoint(x: drawRect.minX, y: drawRect.maxY),
                    CGPoint(x: drawRect.maxX, y: drawRect.maxY)
                ] {
                    drawHandle(at: point, radius: 4.8)
                }
            }
        case .horizontalLine:
            let y = screenPoint(first).y
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(path, with: .color(primary), style: StrokeStyle(lineWidth: 2.0, dash: [8, 6]))
        case .brush:
            guard drawing.points.count > 1 else { return }
            var path = Path()
            path.move(to: screenPoint(drawing.points[0]))
            for point in drawing.points.dropFirst() {
                path.addLine(to: screenPoint(point))
            }
            context.stroke(path, with: .color(primary), style: stroke)
        case .longPosition, .shortPosition:
            drawPosition(drawing, in: rect, context: &context)
        case .paperTrade:
            break
        case .eraser:
            break
        }
    }

    private func drawPosition(_ drawing: ChartDrawing, in rect: CGRect, context: inout GraphicsContext) {
        guard drawing.points.count >= 4 else { return }

        let isLong = drawing.tool == .longPosition
        let entry = drawing.points[0]
        let target = drawing.points[1]
        let stop = drawing.points[2]
        let end = drawing.points[3]

        let leftX = xPosition(for: min(entry.barIndex, end.barIndex), in: rect)
        let rightX = xPosition(for: max(entry.barIndex, end.barIndex), in: rect)
        let entryY = yPosition(for: entry.price, in: rect)
        let targetY = yPosition(for: target.price, in: rect)
        let stopY = yPosition(for: stop.price, in: rect)
        let boxWidth = max(20, rightX - leftX)

        let profitTop = min(entryY, targetY)
        let profitBottom = max(entryY, targetY)
        let lossTop = min(entryY, stopY)
        let lossBottom = max(entryY, stopY)

        context.fill(
            Path(CGRect(x: leftX, y: profitTop, width: boxWidth, height: max(1, profitBottom - profitTop))),
            with: .color(Color.green.opacity(0.25))
        )
        context.fill(
            Path(CGRect(x: leftX, y: lossTop, width: boxWidth, height: max(1, lossBottom - lossTop))),
            with: .color(Color.red.opacity(0.25))
        )

        func horizontalLine(y: CGFloat, color: Color, dash: [CGFloat] = []) {
            var path = Path()
            path.move(to: CGPoint(x: leftX, y: y))
            path.addLine(to: CGPoint(x: rightX, y: y))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, dash: dash))
        }

        horizontalLine(y: targetY, color: .green)
        horizontalLine(y: entryY, color: .black, dash: [5, 4])
        horizontalLine(y: stopY, color: .red)

        var border = Path()
        border.addRoundedRect(in: CGRect(x: leftX, y: min(targetY, stopY), width: boxWidth, height: max(4, abs(targetY - stopY))), cornerSize: CGSize(width: 3, height: 3))
        context.stroke(border, with: .color(Color.black.opacity(0.62)), lineWidth: 1.2)

        let risk = abs(entry.price - stop.price)
        let reward = abs(target.price - entry.price)
        let ratio = risk == 0 ? 0 : reward / risk
        let targetPercent = entry.price == 0 ? 0 : ((target.price - entry.price) / entry.price) * 100
        let stopPercent = entry.price == 0 ? 0 : ((stop.price - entry.price) / entry.price) * 100
        let rrLabel = Text("R:R \(String(format: "%.2g", ratio))")
            .font(.caption2.bold())
            .foregroundStyle(.black)
        let gainLabel = Text("\(isLong ? "Gain" : "Gain") \(abs(targetPercent).percentText)")
            .font(.caption2.bold())
            .foregroundStyle(.black)
        let lossLabel = Text("Loss \(abs(stopPercent).percentText)")
            .font(.caption2.bold())
            .foregroundStyle(.black)

        context.draw(rrLabel, at: CGPoint(x: leftX + boxWidth / 2, y: entryY - 10))
        context.draw(gainLabel, at: CGPoint(x: leftX + boxWidth / 2, y: profitTop + max(12, (profitBottom - profitTop) / 2)))
        context.draw(lossLabel, at: CGPoint(x: leftX + boxWidth / 2, y: lossTop + max(12, (lossBottom - lossTop) / 2)))

        if isReplayMode, let outcome = replayOutcome(for: drawing) {
            let labelText: String
            let labelColor: Color
            switch outcome {
            case .target(let percent):
                labelText = "TP \(abs(percent).percentText)"
                labelColor = .green
            case .stop(let percent):
                labelText = "SL \(abs(percent).percentText)"
                labelColor = .red
            }
            let outcomeLabel = Text(labelText)
                .font(.caption2.bold())
                .foregroundStyle(.white)
            context.drawLayer { layer in
                let labelPoint = CGPoint(x: leftX + boxWidth / 2, y: min(targetY, stopY) - 18)
                let pill = Path(roundedRect: CGRect(x: labelPoint.x - 34, y: labelPoint.y - 10, width: 68, height: 20), cornerRadius: 5)
                layer.fill(pill, with: .color(labelColor.opacity(0.9)))
                layer.draw(outcomeLabel, at: labelPoint)
            }
        }

        let showHandles = drawing.id == selectedDrawingID || drawing.id == draftDrawing?.id
        if showHandles {
            func drawPositionHandle(at point: CGPoint) {
                let outer = Path(ellipseIn: CGRect(x: point.x - 5.4, y: point.y - 5.4, width: 10.8, height: 10.8))
                let inner = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
                context.fill(outer, with: .color(backgroundTheme.isLight ? Color.white.opacity(0.94) : Color.black.opacity(0.78)))
                context.stroke(outer, with: .color(Color.black.opacity(0.88)), lineWidth: 1.4)
                context.fill(inner, with: .color(Color.black.opacity(0.88)))
            }

            let topY = min(targetY, stopY)
            let bottomY = max(targetY, stopY)
            [
                CGPoint(x: leftX, y: topY),
                CGPoint(x: rightX, y: topY),
                CGPoint(x: leftX, y: bottomY),
                CGPoint(x: rightX, y: bottomY),
                CGPoint(x: leftX, y: entryY),
                CGPoint(x: rightX, y: entryY)
            ].forEach(drawPositionHandle)
        }
    }

    private func replayOutcome(for drawing: ChartDrawing) -> ReplayTradeOutcome? {
        guard isReplayMode, renderCandles.count > 1, drawing.points.count >= 3 else { return nil }
        let isLong = drawing.tool == .longPosition
        let entry = drawing.points[0]
        let target = drawing.points[1]
        let stop = drawing.points[2]
        let start = min(max(Int(entry.barIndex.rounded()) + 1, 0), renderCandles.count)
        guard start < renderCandles.count else { return nil }

        for candle in renderCandles[start...] {
            if isLong {
                if candle.low <= stop.price {
                    let percent = entry.price == 0 ? 0 : ((stop.price - entry.price) / entry.price) * 100
                    return .stop(percent)
                }
                if candle.high >= target.price {
                    let percent = entry.price == 0 ? 0 : ((target.price - entry.price) / entry.price) * 100
                    return .target(percent)
                }
            } else {
                if candle.high >= stop.price {
                    let percent = entry.price == 0 ? 0 : ((entry.price - stop.price) / entry.price) * 100
                    return .stop(percent)
                }
                if candle.low <= target.price {
                    let percent = entry.price == 0 ? 0 : ((entry.price - target.price) / entry.price) * 100
                    return .target(percent)
                }
            }
        }

        return nil
    }

    private func plotRect(in size: CGSize) -> CGRect {
        let layout = chartLayout(in: size)
        return CGRect(
            x: 6,
            y: layout.topInset,
            width: max(1, size.width - 60),
            height: layout.chartHeight
        )
    }

    private var verticalGridIndexes: [Int] {
        guard !visibleCandles.isEmpty else { return [] }
        let first = xDomain.lowerBound
        let last = xDomain.upperBound
        let start = Int(ceil(Double(first) / 30.0)) * 30
        guard start <= last else { return [] }
        return Array(stride(from: start, through: last, by: 30))
    }

    private func xPosition(for barIndex: Double, in rect: CGRect) -> CGFloat {
        let xRange = max(Double(xDomain.upperBound - xDomain.lowerBound), 1)
        let xPercent = (barIndex - Double(xDomain.lowerBound)) / xRange
        return rect.minX + rect.width * CGFloat(xPercent)
    }

    private func pointToScreen(_ point: ChartCoordinate, in rect: CGRect) -> CGPoint {
        let yRange = max(yDomain.upperBound - yDomain.lowerBound, 0.0001)
        let yPercent = (point.price - yDomain.lowerBound) / yRange

        return CGPoint(
            x: xPosition(for: point.barIndex, in: rect),
            y: rect.maxY - rect.height * CGFloat(yPercent)
        )
    }

    private func yPosition(for price: Double, in rect: CGRect) -> CGFloat {
        let yRange = max(yDomain.upperBound - yDomain.lowerBound, 0.0001)
        let yPercent = (price - yDomain.lowerBound) / yRange
        return rect.maxY - rect.height * CGFloat(yPercent)
    }

    private func price(atY y: CGFloat, in size: CGSize) -> Double {
        let rect = plotRect(in: size)
        let clampedY = min(max(y, rect.minY), rect.maxY)
        let yPercent = Double((rect.maxY - clampedY) / rect.height)
        return yDomain.lowerBound + (yDomain.upperBound - yDomain.lowerBound) * yPercent
    }

    private func axisPriceLabel(for price: Double) -> String {
        let range = yDomain.upperBound - yDomain.lowerBound
        if range < 2 {
            return String(format: "%.3f", price)
        }
        if range < 20 {
            return String(format: "%.2f", price)
        }
        if price >= 1000 {
            return price.priceText
        }
        return String(format: "%.1f", price)
    }

    private func screenToPoint(_ location: CGPoint, in rect: CGRect) -> ChartCoordinate {
        let clampedX = min(max(location.x, rect.minX), rect.maxX)
        let clampedY = min(max(location.y, rect.minY), rect.maxY)
        let xPercent = Double((clampedX - rect.minX) / rect.width)
        let yPercent = Double((rect.maxY - clampedY) / rect.height)
        let barIndex = Double(xDomain.lowerBound) + Double(xDomain.upperBound - xDomain.lowerBound) * xPercent
        let price = yDomain.lowerBound + (yDomain.upperBound - yDomain.lowerBound) * yPercent
        return ChartCoordinate(barIndex: barIndex, price: price)
    }

    private func handleGesturePanChanged(location: CGPoint, startLocation: CGPoint, translation: CGPoint, size: CGSize) {
        guard !renderCandles.isEmpty, size.width > 0 else { return }

        if let tool = activeTool {
            updateDraft(for: tool, startLocation: startLocation, location: location, rect: plotRect(in: size))
            return
        }

        if updatePaperOrderDrag(location: location, startLocation: startLocation, size: size) {
            return
        }

        if updatePositionDrag(location: location, startLocation: startLocation, size: size) {
            return
        }

        if crosshairLocation != nil {
            updateCrosshair(at: location, in: size)
            return
        }

        updatePan(translationX: translation.x, width: size.width)
    }

    private func handleGesturePanEnded(location: CGPoint, startLocation: CGPoint, translation: CGPoint, size: CGSize) {
        guard !renderCandles.isEmpty else { return }

        if let tool = activeTool {
            finishDraft(for: tool, startLocation: startLocation, location: location, translation: translation, rect: plotRect(in: size))
            if tool != .crosshair {
                draftDrawing = nil
            }
            return
        }

        if paperOrderDragState != nil {
            _ = updatePaperOrderDrag(location: location, startLocation: startLocation, size: size)
            paperOrderDragState = nil
            return
        }

        if positionDragState != nil {
            _ = updatePositionDrag(location: location, startLocation: startLocation, size: size)
            positionDragState = nil
            return
        }

        if crosshairLocation != nil {
            updateCrosshair(at: location, in: size)
        }

        baseEndIndex = nil
    }

    private func updatePositionDrag(location: CGPoint, startLocation: CGPoint, size: CGSize) -> Bool {
        let rect = plotRect(in: size)
        if positionDragState == nil {
            guard let hit = positionHitTest(at: startLocation, in: rect) ?? rayHitTest(at: startLocation, in: rect) ?? measureHitTest(at: startLocation, in: rect) ?? rectangleHitTest(at: startLocation, in: rect) ?? trendLineHitTest(at: startLocation, in: rect) ?? fibHitTest(at: startLocation, in: rect) else { return false }
            recordDrawingHistory()
            selectedDrawingID = hit.drawingID
            positionDragState = hit
        }

        guard let state = positionDragState,
              let index = drawings.firstIndex(where: { $0.id == state.drawingID }) else {
            return false
        }

        let current = screenToPoint(location, in: rect)
        var drawing = state.originalDrawing

        if drawing.tool == .ray {
            guard drawing.points.count >= 2 else { return false }
            let deltaBars = current.barIndex - state.startPoint.barIndex
            let deltaPrice = current.price - state.startPoint.price

            switch state.handle {
            case .rayOrigin:
                drawing.points[0] = clampedChartCoordinate(current)
            case .rayDirection:
                drawing.points[1] = clampedChartCoordinate(current)
            case .rayMove:
                for pointIndex in 0..<drawing.points.count {
                    drawing.points[pointIndex] = clampedChartCoordinate(
                        ChartCoordinate(
                            barIndex: state.originalDrawing.points[pointIndex].barIndex + deltaBars,
                            price: state.originalDrawing.points[pointIndex].price + deltaPrice
                        )
                    )
                }
            default:
                return false
            }

            drawings[index] = drawing
            return true
        }

        if drawing.tool == .measure {
            guard drawing.points.count >= 2 else { return false }
            let deltaBars = current.barIndex - state.startPoint.barIndex
            let deltaPrice = current.price - state.startPoint.price

            switch state.handle {
            case .measureStart:
                drawing.points[0] = clampedChartCoordinate(current)
            case .measureEnd:
                drawing.points[1] = clampedChartCoordinate(current)
            case .measureMove:
                for pointIndex in 0..<drawing.points.count {
                    drawing.points[pointIndex] = clampedChartCoordinate(
                        ChartCoordinate(
                            barIndex: state.originalDrawing.points[pointIndex].barIndex + deltaBars,
                            price: state.originalDrawing.points[pointIndex].price + deltaPrice
                        )
                    )
                }
            default:
                return false
            }

            drawings[index] = drawing
            return true
        }

        if drawing.tool == .rectangle {
            guard drawing.points.count >= 2 else { return false }
            let deltaBars = current.barIndex - state.startPoint.barIndex
            let deltaPrice = current.price - state.startPoint.price

            switch state.handle {
            case .rectangleTopLeft:
                drawing.points[0] = clampedChartCoordinate(current)
            case .rectangleBottomRight:
                drawing.points[1] = clampedChartCoordinate(current)
            case .rectangleTopRight:
                drawing.points[0] = ChartCoordinate(barIndex: drawing.points[0].barIndex, price: current.price)
                drawing.points[1] = ChartCoordinate(barIndex: current.barIndex, price: drawing.points[1].price)
            case .rectangleBottomLeft:
                drawing.points[0] = ChartCoordinate(barIndex: current.barIndex, price: drawing.points[0].price)
                drawing.points[1] = ChartCoordinate(barIndex: drawing.points[1].barIndex, price: current.price)
            case .rectangleMove:
                for pointIndex in 0..<drawing.points.count {
                    drawing.points[pointIndex] = clampedChartCoordinate(
                        ChartCoordinate(
                            barIndex: state.originalDrawing.points[pointIndex].barIndex + deltaBars,
                            price: state.originalDrawing.points[pointIndex].price + deltaPrice
                        )
                    )
                }
            default:
                return false
            }

            drawings[index] = drawing
            return true
        }

        if drawing.tool == .trendLine {
            guard drawing.points.count >= 2 else { return false }
            let deltaBars = current.barIndex - state.startPoint.barIndex
            let deltaPrice = current.price - state.startPoint.price

            switch state.handle {
            case .lineStart:
                drawing.points[0] = clampedChartCoordinate(current)
            case .lineEnd:
                drawing.points[1] = clampedChartCoordinate(current)
            case .lineMove:
                for pointIndex in 0..<drawing.points.count {
                    drawing.points[pointIndex] = clampedChartCoordinate(
                        ChartCoordinate(
                            barIndex: state.originalDrawing.points[pointIndex].barIndex + deltaBars,
                            price: state.originalDrawing.points[pointIndex].price + deltaPrice
                        )
                    )
                }
            default:
                return false
            }

            drawings[index] = drawing
            return true
        }

        if drawing.tool == .fibRetracement {
            guard drawing.points.count >= 2 else { return false }
            let deltaBars = current.barIndex - state.startPoint.barIndex
            let deltaPrice = current.price - state.startPoint.price

            switch state.handle {
            case .fibStart:
                drawing.points[0] = clampedChartCoordinate(current)
            case .fibEnd:
                drawing.points[1] = clampedChartCoordinate(current)
            case .fibMove:
                for pointIndex in 0..<drawing.points.count {
                    drawing.points[pointIndex] = clampedChartCoordinate(
                        ChartCoordinate(
                            barIndex: state.originalDrawing.points[pointIndex].barIndex + deltaBars,
                            price: state.originalDrawing.points[pointIndex].price + deltaPrice
                        )
                    )
                }
            default:
                return false
            }

            drawings[index] = drawing
            return true
        }

        guard drawing.points.count >= 4 else { return false }

        let minWidth = 2.0
        func leftBar(_ requested: Double) -> Double {
            min(max(requested, 0), drawing.points[3].barIndex - minWidth)
        }

        func rightBar(_ requested: Double) -> Double {
            max(drawing.points[0].barIndex + minWidth, min(Double(max(renderCandles.count - 1, 0)), requested))
        }

        switch state.handle {
        case .move, .entry:
            let deltaBars = current.barIndex - state.startPoint.barIndex
            let deltaPrice = current.price - state.startPoint.price
            for pointIndex in 0..<drawing.points.count {
                drawing.points[pointIndex] = ChartCoordinate(
                    barIndex: min(max(state.originalDrawing.points[pointIndex].barIndex + deltaBars, 0), Double(max(renderCandles.count - 1, 0))),
                    price: state.originalDrawing.points[pointIndex].price + deltaPrice
                )
            }
        case .target:
            drawing.points[1] = ChartCoordinate(barIndex: drawing.points[1].barIndex, price: current.price)
        case .stop:
            drawing.points[2] = ChartCoordinate(barIndex: drawing.points[2].barIndex, price: current.price)
        case .duration:
            let deltaBars = current.barIndex - state.startPoint.barIndex
            let originalEnd = state.originalDrawing.points[3].barIndex
            let newEnd = max(drawing.points[0].barIndex + minWidth, min(Double(max(renderCandles.count - 1, 0)), originalEnd + deltaBars))
            drawing.points[3] = ChartCoordinate(barIndex: newEnd, price: drawing.points[0].price)
        case .positionTargetLeft:
            drawing.points[0] = ChartCoordinate(barIndex: leftBar(current.barIndex), price: drawing.points[0].price)
            drawing.points[1] = ChartCoordinate(barIndex: drawing.points[1].barIndex, price: current.price)
        case .positionTargetRight:
            drawing.points[1] = ChartCoordinate(barIndex: drawing.points[1].barIndex, price: current.price)
            drawing.points[3] = ChartCoordinate(barIndex: rightBar(current.barIndex), price: drawing.points[0].price)
        case .positionStopLeft:
            drawing.points[0] = ChartCoordinate(barIndex: leftBar(current.barIndex), price: drawing.points[0].price)
            drawing.points[2] = ChartCoordinate(barIndex: drawing.points[2].barIndex, price: current.price)
        case .positionStopRight:
            drawing.points[2] = ChartCoordinate(barIndex: drawing.points[2].barIndex, price: current.price)
            drawing.points[3] = ChartCoordinate(barIndex: rightBar(current.barIndex), price: drawing.points[0].price)
        case .positionEntryLeft:
            drawing.points[0] = ChartCoordinate(barIndex: leftBar(current.barIndex), price: current.price)
            drawing.points[3] = ChartCoordinate(barIndex: drawing.points[3].barIndex, price: current.price)
        case .positionEntryRight:
            drawing.points[0] = ChartCoordinate(barIndex: drawing.points[0].barIndex, price: current.price)
            drawing.points[3] = ChartCoordinate(barIndex: rightBar(current.barIndex), price: current.price)
        case .rayOrigin, .rayDirection, .rayMove, .measureStart, .measureEnd, .measureMove, .rectangleTopLeft, .rectangleTopRight, .rectangleBottomLeft, .rectangleBottomRight, .rectangleMove, .lineStart, .lineEnd, .lineMove, .fibStart, .fibEnd, .fibMove:
            return false
        }

        drawings[index] = drawing
        return true
    }

    private func updatePaperOrderDrag(location: CGPoint, startLocation: CGPoint, size: CGSize) -> Bool {
        let rect = plotRect(in: size)
        if paperOrderDragState == nil {
            guard let hit = paperOrderHitTest(at: startLocation, in: rect) else { return false }
            if hit.handle == .cancel,
               let order = paperTrading.account.pendingOrders.first(where: { $0.id == hit.orderID && paperObjectIsVisible(symbol: $0.symbol, isReplayTrade: $0.isReplayTrade) }) {
                paperTrading.cancelOrder(order)
                selectedPaperOrderID = nil
                return true
            }
            paperOrderDragState = hit
            selectedPaperOrderID = hit.orderID
        }

        guard let state = paperOrderDragState else { return false }
        let price = screenToPoint(location, in: rect).price
        switch state.handle {
        case .entry:
            guard let order = paperTrading.account.pendingOrders.first(where: { $0.id == state.orderID && paperObjectIsVisible(symbol: $0.symbol, isReplayTrade: $0.isReplayTrade) }),
                  paperOrderEntryIsEditable(order) else {
                return true
            }
            paperTrading.updatePendingOrder(state.orderID, entryPrice: price)
        case .stop:
            paperTrading.updatePendingOrder(state.orderID, stopLoss: price)
        case .target:
            paperTrading.updatePendingOrder(state.orderID, takeProfit: price)
        case .cancel:
            return false
        }
        return true
    }

    private func paperOrderHitTest(at location: CGPoint, in rect: CGRect) -> PaperOrderDragState? {
        let tolerance: CGFloat = 18
        for order in paperTrading.account.pendingOrders.reversed() where paperObjectIsVisible(symbol: order.symbol, isReplayTrade: order.isReplayTrade) {
            let entryY = yPosition(for: order.entryPrice, in: rect)
            let pillX = rect.minX + min(210, rect.width * 0.36)
            let cancelRect = CGRect(x: pillX + 58, y: entryY - 22, width: 54, height: 44)
            if cancelRect.contains(location) {
                return PaperOrderDragState(orderID: order.id, handle: .cancel)
            }
            if let takeProfit = order.takeProfit, abs(location.y - yPosition(for: takeProfit, in: rect)) <= tolerance {
                return PaperOrderDragState(orderID: order.id, handle: .target)
            }
            if let stopLoss = order.stopLoss, abs(location.y - yPosition(for: stopLoss, in: rect)) <= tolerance {
                return PaperOrderDragState(orderID: order.id, handle: .stop)
            }
            if abs(location.y - entryY) <= tolerance {
                return PaperOrderDragState(orderID: order.id, handle: .entry)
            }
        }
        return nil
    }

    private func paperOrderEntryIsEditable(_ order: SimulatedOrder) -> Bool {
        guard !isReplayMode, let latestBarIndex = candles.last?.index else { return false }
        return order.createdBarIndex == latestBarIndex
    }

    private func selectPaperOrder(at location: CGPoint, in size: CGSize) -> Bool {
        let rect = plotRect(in: size)
        guard let hit = paperOrderHitTest(at: location, in: rect) else {
            selectedPaperOrderID = nil
            return false
        }

        if hit.handle == .cancel,
           let order = paperTrading.account.pendingOrders.first(where: { $0.id == hit.orderID && paperObjectIsVisible(symbol: $0.symbol, isReplayTrade: $0.isReplayTrade) }) {
            paperTrading.cancelOrder(order)
            selectedPaperOrderID = nil
            return true
        }

        selectedPaperOrderID = hit.orderID
        return true
    }

    private func clampedChartCoordinate(_ point: ChartCoordinate) -> ChartCoordinate {
        ChartCoordinate(
            barIndex: min(max(point.barIndex, 0), Double(max(renderCandles.count - 1, 0))),
            price: point.price
        )
    }

    private func positionHitTest(at location: CGPoint, in rect: CGRect) -> PositionDragState? {
        let lineTolerance: CGFloat = 16
        let handleTolerance: CGFloat = 24
        let bodyTolerance: CGFloat = 20

        for drawing in drawings.reversed() where drawing.tool == .longPosition || drawing.tool == .shortPosition {
            guard drawing.points.count >= 4 else { continue }

            let entryY = yPosition(for: drawing.points[0].price, in: rect)
            let targetY = yPosition(for: drawing.points[1].price, in: rect)
            let stopY = yPosition(for: drawing.points[2].price, in: rect)
            let leftX = xPosition(for: drawing.points[0].barIndex, in: rect)
            let rightX = xPosition(for: drawing.points[3].barIndex, in: rect)
            let topY = min(targetY, stopY)
            let bottomY = max(targetY, stopY)
            let withinX = location.x >= min(leftX, rightX) - lineTolerance && location.x <= max(leftX, rightX) + lineTolerance

            func near(_ point: CGPoint) -> Bool {
                hypot(location.x - point.x, location.y - point.y) <= handleTolerance
            }

            if near(CGPoint(x: leftX, y: targetY)) {
                return PositionDragState(drawingID: drawing.id, handle: .positionTargetLeft, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if near(CGPoint(x: rightX, y: targetY)) {
                return PositionDragState(drawingID: drawing.id, handle: .positionTargetRight, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if near(CGPoint(x: leftX, y: stopY)) {
                return PositionDragState(drawingID: drawing.id, handle: .positionStopLeft, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if near(CGPoint(x: rightX, y: stopY)) {
                return PositionDragState(drawingID: drawing.id, handle: .positionStopRight, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if near(CGPoint(x: leftX, y: entryY)) {
                return PositionDragState(drawingID: drawing.id, handle: .positionEntryLeft, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if near(CGPoint(x: rightX, y: entryY)) {
                return PositionDragState(drawingID: drawing.id, handle: .positionEntryRight, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            if withinX && abs(location.y - entryY) <= lineTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .entry, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if withinX && abs(location.y - targetY) <= lineTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .target, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if withinX && abs(location.y - stopY) <= lineTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .stop, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if abs(location.x - rightX) <= lineTolerance && location.y >= topY - lineTolerance && location.y <= bottomY + lineTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .duration, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if location.x >= min(leftX, rightX) - bodyTolerance && location.x <= max(leftX, rightX) + bodyTolerance && location.y >= topY - bodyTolerance && location.y <= bottomY + bodyTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .move, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
        }

        return nil
    }

    private func rayHitTest(at location: CGPoint, in rect: CGRect) -> PositionDragState? {
        let anchorTolerance: CGFloat = 20
        let lineTolerance: CGFloat = 16

        for drawing in drawings.reversed() where drawing.tool == .ray {
            guard drawing.points.count >= 2 else { continue }
            let start = pointToScreen(drawing.points[0], in: rect)
            let direction = pointToScreen(drawing.points[1], in: rect)

            if hypot(location.x - start.x, location.y - start.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .rayOrigin, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            if hypot(location.x - direction.x, location.y - direction.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .rayDirection, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            let dx = abs(direction.x - start.x) < 0.1 ? 1 : direction.x - start.x
            let slope = (direction.y - start.y) / dx
            let projectedEnd = CGPoint(x: rect.maxX, y: start.y + slope * (rect.maxX - start.x))
            if distanceToSegment(location, start, projectedEnd) <= lineTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .rayMove, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
        }

        return nil
    }

    private func measureHitTest(at location: CGPoint, in rect: CGRect) -> PositionDragState? {
        let anchorTolerance: CGFloat = 20
        let lineTolerance: CGFloat = 16

        for drawing in drawings.reversed() where drawing.tool == .measure {
            guard drawing.points.count >= 2 else { continue }
            let start = pointToScreen(drawing.points[0], in: rect)
            let end = pointToScreen(drawing.points[1], in: rect)

            if hypot(location.x - start.x, location.y - start.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .measureStart, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            if hypot(location.x - end.x, location.y - end.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .measureEnd, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            if distanceToSegment(location, start, end) <= lineTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .measureMove, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
        }

        return nil
    }

    private func rectangleHitTest(at location: CGPoint, in rect: CGRect) -> PositionDragState? {
        let anchorTolerance: CGFloat = 20
        let edgeTolerance: CGFloat = 14

        for drawing in drawings.reversed() where drawing.tool == .rectangle {
            guard drawing.points.count >= 2 else { continue }
            let first = pointToScreen(drawing.points[0], in: rect)
            let last = pointToScreen(drawing.points[1], in: rect)
            let topLeft = CGPoint(x: min(first.x, last.x), y: min(first.y, last.y))
            let topRight = CGPoint(x: max(first.x, last.x), y: min(first.y, last.y))
            let bottomLeft = CGPoint(x: min(first.x, last.x), y: max(first.y, last.y))
            let bottomRight = CGPoint(x: max(first.x, last.x), y: max(first.y, last.y))
            let drawRect = CGRect(
                x: topLeft.x,
                y: topLeft.y,
                width: topRight.x - topLeft.x,
                height: bottomLeft.y - topLeft.y
            )

            if hypot(location.x - topLeft.x, location.y - topLeft.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .rectangleTopLeft, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if hypot(location.x - topRight.x, location.y - topRight.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .rectangleTopRight, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if hypot(location.x - bottomLeft.x, location.y - bottomLeft.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .rectangleBottomLeft, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if hypot(location.x - bottomRight.x, location.y - bottomRight.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .rectangleBottomRight, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
            if drawRect.insetBy(dx: -edgeTolerance, dy: -edgeTolerance).contains(location) {
                return PositionDragState(drawingID: drawing.id, handle: .rectangleMove, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
        }

        return nil
    }

    private func trendLineHitTest(at location: CGPoint, in rect: CGRect) -> PositionDragState? {
        let anchorTolerance: CGFloat = 20
        let lineTolerance: CGFloat = 16

        for drawing in drawings.reversed() where drawing.tool == .trendLine {
            guard drawing.points.count >= 2 else { continue }
            let start = pointToScreen(drawing.points[0], in: rect)
            let end = pointToScreen(drawing.points[1], in: rect)

            if hypot(location.x - start.x, location.y - start.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .lineStart, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            if hypot(location.x - end.x, location.y - end.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .lineEnd, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            if distanceToSegment(location, start, end) <= lineTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .lineMove, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }
        }

        return nil
    }

    private func fibHitTest(at location: CGPoint, in rect: CGRect) -> PositionDragState? {
        let anchorTolerance: CGFloat = 20
        let lineTolerance: CGFloat = 16

        for drawing in drawings.reversed() where drawing.tool == .fibRetracement {
            guard drawing.points.count >= 2 else { continue }
            let start = pointToScreen(drawing.points[0], in: rect)
            let end = pointToScreen(drawing.points[1], in: rect)

            if hypot(location.x - start.x, location.y - start.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .fibStart, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            if hypot(location.x - end.x, location.y - end.y) <= anchorTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .fibEnd, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            if distanceToSegment(location, start, end) <= lineTolerance {
                return PositionDragState(drawingID: drawing.id, handle: .fibMove, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
            }

            guard location.x >= rect.minX - lineTolerance, location.x <= rect.maxX + lineTolerance else { continue }
            for level in fibLevels {
                let price = drawing.points[0].price + (drawing.points[1].price - drawing.points[0].price) * level
                if abs(location.y - yPosition(for: price, in: rect)) <= lineTolerance {
                    return PositionDragState(drawingID: drawing.id, handle: .fibMove, startPoint: screenToPoint(location, in: rect), originalDrawing: drawing)
                }
            }
        }

        return nil
    }

    private func distanceToSegment(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func removeDrawing(at location: CGPoint, in size: CGSize) {
        let rect = plotRect(in: size)
        guard let drawing = drawings.reversed().first(where: { drawingContains($0, at: location, in: rect) }),
              let index = drawings.firstIndex(where: { $0.id == drawing.id }) else {
            return
        }

        recordDrawingHistory()
        drawings.remove(at: index)
        if selectedDrawingID == drawing.id {
            selectedDrawingID = nil
        }
    }

    private func selectEditableDrawing(at location: CGPoint, in size: CGSize) {
        let rect = plotRect(in: size)
        selectedDrawingID = drawings.reversed().first { drawing in
            (drawing.tool == .rectangle || drawing.tool == .trendLine || drawing.tool == .fibRetracement || drawing.tool == .longPosition || drawing.tool == .shortPosition) && drawingContains(drawing, at: location, in: rect)
        }?.id
    }

    private func drawingContains(_ drawing: ChartDrawing, at location: CGPoint, in rect: CGRect) -> Bool {
        let tolerance: CGFloat = 18

        func screenPoint(_ point: ChartCoordinate) -> CGPoint {
            pointToScreen(point, in: rect)
        }

        guard let first = drawing.points.first else { return false }

        switch drawing.tool {
        case .crosshair:
            let point = screenPoint(first)
            return abs(location.x - point.x) <= tolerance || abs(location.y - point.y) <= tolerance
        case .horizontalLine:
            return abs(location.y - screenPoint(first).y) <= tolerance
        case .trendLine, .measure:
            guard let last = drawing.points.last else { return false }
            return distanceToSegment(location, screenPoint(first), screenPoint(last)) <= tolerance
        case .fibRetracement:
            guard drawing.points.count >= 2 else { return false }
            let firstAnchor = drawing.points[0]
            let secondAnchor = drawing.points[1]
            if distanceToSegment(location, screenPoint(firstAnchor), screenPoint(secondAnchor)) <= tolerance {
                return true
            }
            let minX = rect.minX - tolerance
            let maxX = rect.maxX + tolerance
            guard location.x >= minX, location.x <= maxX else { return false }
            return fibLevels.contains { level in
                let price = firstAnchor.price + (secondAnchor.price - firstAnchor.price) * level
                return abs(location.y - yPosition(for: price, in: rect)) <= tolerance
            }
        case .ray:
            guard let last = drawing.points.last else { return false }
            let start = screenPoint(first)
            let end = screenPoint(last)
            let dx = abs(end.x - start.x) < 0.1 ? 1 : end.x - start.x
            let slope = (end.y - start.y) / dx
            let rayEnd = CGPoint(x: rect.maxX, y: start.y + slope * (rect.maxX - start.x))
            return distanceToSegment(location, start, rayEnd) <= tolerance
        case .rectangle:
            guard let last = drawing.points.last else { return false }
            let start = screenPoint(first)
            let end = screenPoint(last)
            let drawRect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ).insetBy(dx: -tolerance, dy: -tolerance)
            return drawRect.contains(location)
        case .brush:
            guard drawing.points.count > 1 else { return false }
            for index in 1..<drawing.points.count {
                if distanceToSegment(location, screenPoint(drawing.points[index - 1]), screenPoint(drawing.points[index])) <= tolerance {
                    return true
                }
            }
            return false
        case .longPosition, .shortPosition:
            guard drawing.points.count >= 4 else { return false }
            let entryY = yPosition(for: drawing.points[0].price, in: rect)
            let targetY = yPosition(for: drawing.points[1].price, in: rect)
            let stopY = yPosition(for: drawing.points[2].price, in: rect)
            let leftX = xPosition(for: min(drawing.points[0].barIndex, drawing.points[3].barIndex), in: rect)
            let rightX = xPosition(for: max(drawing.points[0].barIndex, drawing.points[3].barIndex), in: rect)
            let box = CGRect(
                x: leftX,
                y: min(targetY, stopY),
                width: max(1, rightX - leftX),
                height: max(1, abs(targetY - stopY))
            ).insetBy(dx: -tolerance, dy: -tolerance)
            return box.contains(location) ||
                abs(location.y - entryY) <= tolerance ||
                abs(location.y - targetY) <= tolerance ||
                abs(location.y - stopY) <= tolerance
        case .paperTrade:
            return false
        case .eraser:
            return false
        }
    }

    private func handlePinchChanged(_ scale: CGFloat) {
        guard !renderCandles.isEmpty, activeTool == nil, crosshairLocation == nil else { return }
        let proposed = Int(Double(baseVisibleCount) / Double(scale))
        visibleCount = min(max(proposed, 24), renderCandles.count)
        endIndex = min(max(endIndex ?? renderCandles.count - 1, minimumEndIndex), maximumEndIndex)
    }

    private func handlePinchEnded() {
        guard activeTool == nil, crosshairLocation == nil else { return }
        baseEndIndex = nil
        baseVisibleCount = visibleCount
    }

    private func chartInteractionGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !renderCandles.isEmpty, size.width > 0 else { return }

                guard let tool = activeTool else {
                    handlePanOrCrosshair(value, size: size)
                    return
                }

                updateDraft(for: tool, value: value, rect: plotRect(in: size))
            }
            .onEnded { value in
                guard !renderCandles.isEmpty else { return }

                guard let tool = activeTool else {
                    finishPanOrCrosshair(value)
                    baseEndIndex = nil
                    return
                }

                finishDraft(for: tool, value: value, rect: plotRect(in: size))
                if tool != .crosshair {
                    draftDrawing = nil
                }
            }
    }

    private func resetViewport(candleCount: Int) {
        visibleCount = initialVisibleCount(for: candleCount)
        baseVisibleCount = visibleCount
        endIndex = candleCount - 1
        baseEndIndex = nil
        draftDrawing = nil
        positionDragState = nil
        updateLastVisibleCandle()
    }

    private func initialVisibleCount(for candleCount: Int) -> Int {
        guard candleCount > 0 else { return visibleCount }
        guard candleCount > 24 else { return candleCount }

        let halfHistory = max(36, candleCount / 2)
        return min(120, halfHistory, candleCount)
    }

    private func updatePan(_ value: DragGesture.Value, width: CGFloat) {
        updatePan(translationX: value.translation.width, width: width)
    }

    private func updatePan(translationX: CGFloat, width: CGFloat) {
        if baseEndIndex == nil {
            baseEndIndex = clampedEndIndex
        }

        let barsMoved = Int((-translationX / width) * CGFloat(clampedVisibleCount))
        let proposed = (baseEndIndex ?? clampedEndIndex) + barsMoved
        endIndex = min(max(proposed, minimumEndIndex), maximumEndIndex)
        updateLastVisibleCandle()
    }

    private func updateLastVisibleCandle() {
        lastVisibleCandle = visibleCandles.last
    }

    private func handlePanOrCrosshair(_ value: DragGesture.Value, size: CGSize) {
        if crosshairLocation != nil {
            updateCrosshair(at: value.location, in: size)
            return
        }

        if longPressStartLocation == nil {
            longPressStartLocation = value.startLocation
            scheduleCrosshairActivation(from: value, size: size)
        }

        let horizontalDistance = abs(value.location.x - value.startLocation.x)
        let verticalDistance = abs(value.location.y - value.startLocation.y)
        if horizontalDistance > 4 && horizontalDistance > verticalDistance {
            cancelCrosshairActivation()
            updatePan(value, width: size.width)
        }
    }

    private func scheduleCrosshairActivation(from value: DragGesture.Value, size: CGSize) {
        cancelCrosshairActivation()

        let workItem = DispatchWorkItem {
            let horizontalDistance = abs(value.location.x - value.startLocation.x)
            let verticalDistance = abs(value.location.y - value.startLocation.y)
            guard horizontalDistance <= 4 || horizontalDistance <= verticalDistance else { return }
            baseEndIndex = nil
            updateCrosshair(at: value.location, in: size)
            crosshairActivatedDuringGesture = true
        }

        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func cancelCrosshairActivation() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
    }

    private func clearLongPressCrosshair() {
        cancelCrosshairActivation()
        crosshairLocation = nil
        crosshairCandle = nil
        longPressStartLocation = nil
        crosshairActivatedDuringGesture = false
    }

    private func finishPanOrCrosshair(_ value: DragGesture.Value) {
        let distance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)

        if crosshairLocation != nil {
            if !crosshairActivatedDuringGesture && distance < 8 {
                clearLongPressCrosshair()
            } else {
                cancelCrosshairActivation()
                longPressStartLocation = nil
                crosshairActivatedDuringGesture = false
            }
            return
        }

        cancelCrosshairActivation()
        longPressStartLocation = nil
        crosshairActivatedDuringGesture = false
    }

    private func clampedLocation(_ location: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(location.x, 0), size.width),
            y: min(max(location.y, 0), size.height)
        )
    }

    private func updateCrosshair(at location: CGPoint, in size: CGSize) {
        let clamped = clampedLocation(location, in: size)
        guard let nearestCandle = nearestVisibleCandle(toX: clamped.x, in: size) else {
            crosshairLocation = clamped
            crosshairCandle = nil
            return
        }

        let snappedX = xPosition(for: Double(nearestCandle.index), in: plotRect(in: size))
        crosshairLocation = CGPoint(x: snappedX, y: clamped.y)
        crosshairCandle = nearestCandle
    }

    private func nearestVisibleCandle(toX x: CGFloat, in size: CGSize) -> Candle? {
        let rect = plotRect(in: size)
        let point = screenToPoint(CGPoint(x: x, y: rect.midY), in: rect)
        return visibleCandles.min { first, second in
            abs(Double(first.index) - point.barIndex) < abs(Double(second.index) - point.barIndex)
        }
    }

    private func crosshairDateLabel(for date: Date) -> String {
        interval == .oneDay ? date.chartLabel : date.crosshairIntradayLabel
    }

    private func updateDraft(for tool: DrawingTool, value: DragGesture.Value, rect: CGRect) {
        updateDraft(for: tool, startLocation: value.startLocation, location: value.location, rect: rect)
    }

    private func updateDraft(for tool: DrawingTool, startLocation: CGPoint, location: CGPoint, rect: CGRect) {
        let start = screenToPoint(startLocation, in: rect)
        let current = screenToPoint(location, in: rect)

        switch tool {
        case .eraser:
            draftDrawing = nil
        case .paperTrade:
            draftDrawing = nil
        case .crosshair:
            draftDrawing = ChartDrawing(tool: tool, points: [current])
        case .horizontalLine:
            draftDrawing = ChartDrawing(tool: tool, points: [current])
        case .brush:
            if draftDrawing?.tool != .brush {
                draftDrawing = ChartDrawing(tool: tool, points: [start])
            }
            draftDrawing?.points.append(current)
        case .longPosition, .shortPosition:
            draftDrawing = positionDraft(for: tool, start: start, current: current)
        case .ray:
            draftDrawing = ChartDrawing(tool: tool, points: [pendingRayStart ?? start, current])
        case .fibRetracement:
            draftDrawing = ChartDrawing(tool: tool, points: [pendingFibStart ?? start, current])
        case .trendLine, .rectangle, .measure:
            draftDrawing = ChartDrawing(tool: tool, points: [start, current])
        }
    }

    private func positionDraft(for tool: DrawingTool, start: ChartCoordinate, current: ChartCoordinate) -> ChartDrawing {
        let visibleRange = max(yDomain.upperBound - yDomain.lowerBound, 0.01)
        let defaultRisk = visibleRange * 0.06
        let width = max(abs(current.barIndex - start.barIndex), Double(max(8, clampedVisibleCount / 6)))
        let endBar = min(Double(max(renderCandles.count - 1, 0)), start.barIndex + width)

        let targetPrice: Double
        let stopPrice: Double
        if tool == .longPosition {
            targetPrice = start.price + defaultRisk * 2
            stopPrice = start.price - defaultRisk
        } else {
            targetPrice = start.price - defaultRisk * 2
            stopPrice = start.price + defaultRisk
        }

        return ChartDrawing(
            tool: tool,
            points: [
                ChartCoordinate(barIndex: start.barIndex, price: start.price),
                ChartCoordinate(barIndex: start.barIndex, price: targetPrice),
                ChartCoordinate(barIndex: start.barIndex, price: stopPrice),
                ChartCoordinate(barIndex: endBar, price: start.price)
            ]
        )
    }

    private func placePositionDrawing(at location: CGPoint, in size: CGSize) {
        guard let tool = activeTool, tool == .longPosition || tool == .shortPosition else { return }
        let rect = plotRect(in: size)
        let entry = screenToPoint(location, in: rect)
        let end = ChartCoordinate(
            barIndex: min(Double(max(renderCandles.count - 1, 0)), entry.barIndex + Double(max(8, clampedVisibleCount / 6))),
            price: entry.price
        )
        recordDrawingHistory()
        drawings.append(positionDraft(for: tool, start: entry, current: end))
        selectedDrawingID = nil
        activeTool = nil
    }

    private func placePaperTrade(at location: CGPoint, in size: CGSize) {
        let rect = plotRect(in: size)
        let point = screenToPoint(location, in: rect)
        let nearest = nearestVisibleCandle(toX: location.x, in: size) ?? visibleCandles.last
        paperTrading.configureInstrument(symbol)
        if !isReplayMode, let latest = renderCandles.last {
            if let nearest, nearest.index < latest.index {
                notifyOrderPlacedOnCurrentPrice()
            }
            _ = paperTrading.submitChartOrder(symbol: symbol.ticker, price: latest.close, candle: latest)
            activeTool = nil
            return
        }
        _ = paperTrading.submitChartOrder(symbol: symbol.ticker, price: point.price, candle: nearest)
        activeTool = nil
    }

    private func placeRayPoint(at location: CGPoint, in size: CGSize) {
        guard activeTool == .ray else { return }
        let rect = plotRect(in: size)
        let point = screenToPoint(location, in: rect)

        if let start = pendingRayStart {
            guard abs(point.barIndex - start.barIndex) > 0.01 || abs(point.price - start.price) > 0.01 else { return }
            recordDrawingHistory()
            drawings.append(ChartDrawing(tool: .ray, points: [start, point]))
            selectedDrawingID = nil
            pendingRayStart = nil
            activeTool = nil
            draftDrawing = nil
        } else {
            pendingRayStart = point
            draftDrawing = nil
        }
    }

    private func placeFibPoint(at location: CGPoint, in size: CGSize) {
        guard activeTool == .fibRetracement else { return }
        let rect = plotRect(in: size)
        let point = screenToPoint(location, in: rect)

        if let start = pendingFibStart {
            guard abs(point.barIndex - start.barIndex) > 0.01 || abs(point.price - start.price) > 0.01 else { return }
            recordDrawingHistory()
            drawings.append(ChartDrawing(tool: .fibRetracement, points: [start, point]))
            selectedDrawingID = nil
            pendingFibStart = nil
            activeTool = nil
            draftDrawing = nil
        } else {
            pendingFibStart = point
            draftDrawing = nil
        }
    }

    private func finishDraft(for tool: DrawingTool, value: DragGesture.Value, rect: CGRect) {
        finishDraft(
            for: tool,
            startLocation: value.startLocation,
            location: value.location,
            translation: CGPoint(x: value.translation.width, y: value.translation.height),
            rect: rect
        )
    }

    private func finishDraft(for tool: DrawingTool, startLocation: CGPoint, location: CGPoint, translation: CGPoint, rect: CGRect) {
        updateDraft(for: tool, startLocation: startLocation, location: location, rect: rect)

        guard tool != .crosshair,
              tool != .eraser,
              let draftDrawing,
              draftDrawing.points.count > 0 else {
            return
        }

        let distance = hypot(translation.x, translation.y)
        if tool == .horizontalLine || tool == .brush || tool == .longPosition || tool == .shortPosition || distance > 6 {
            recordDrawingHistory()
            drawings.append(draftDrawing)
            selectedDrawingID = nil
            if tool == .ray {
                pendingRayStart = nil
            }
            if tool == .fibRetracement {
                pendingFibStart = nil
            }
            if shouldDeactivateAfterPlacement(tool) {
                activeTool = nil
            }
        }
    }

    private func shouldDeactivateAfterPlacement(_ tool: DrawingTool) -> Bool {
        switch tool {
        case .brush, .crosshair, .eraser:
            return false
        case .trendLine, .rectangle, .horizontalLine, .measure, .ray, .fibRetracement, .longPosition, .shortPosition, .paperTrade:
            return true
        }
    }

    private var chartZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard !renderCandles.isEmpty, activeTool == nil, crosshairLocation == nil else { return }
                let proposed = Int(Double(baseVisibleCount) / value)
                visibleCount = min(max(proposed, 24), renderCandles.count)
                endIndex = min(max(endIndex ?? renderCandles.count - 1, minimumEndIndex), maximumEndIndex)
            }
            .onEnded { _ in
                guard activeTool == nil, crosshairLocation == nil else { return }
                baseEndIndex = nil
                baseVisibleCount = visibleCount
            }
    }

    private var vwapPoints: [VWAPPoint] {
        var points: [VWAPPoint] = []
        var currentSession: Date?
        var cumulativeVolume = 0.0
        var cumulativePriceVolume = 0.0
        var cumulativeVarianceVolume = 0.0
        let calendar = Calendar.current
        let visibleIndexes = Set(visibleCandles.map(\.index))
        guard !visibleIndexes.isEmpty else { return [] }

        for candle in vwapSourceCandles {
            let session = calendar.startOfDay(for: candle.date)
            if currentSession != session {
                currentSession = session
                cumulativeVolume = 0
                cumulativePriceVolume = 0
                cumulativeVarianceVolume = 0
            }

            let source = (candle.open + candle.high + candle.low + candle.close) / 4
            let volume = max(candle.volume, 1)
            cumulativeVolume += volume
            cumulativePriceVolume += source * volume
            let vwap = cumulativePriceVolume / cumulativeVolume

            cumulativeVarianceVolume += pow(source - vwap, 2) * volume
            let deviation = sqrt(max(cumulativeVarianceVolume / cumulativeVolume, 0))

            if visibleIndexes.contains(candle.index) {
                points.append(
                    VWAPPoint(
                        index: candle.index,
                        value: vwap,
                        upperBand: vwap + deviation,
                        lowerBand: vwap - deviation
                    )
                )
            }
        }

        return points
    }

    private var vwapSourceCandles: [Candle] {
        guard !renderCandles.isEmpty else { return [] }
        if isReplayMode,
           replayCandleProgress < 1,
           let lastIndex = renderCandles.indices.last {
            var candles = renderCandles
            candles[lastIndex] = formingCandle(from: candles[lastIndex], progress: replayCandleProgress)
            return candles
        }
        return renderCandles
    }
}

private struct ChannelOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.02))
        return path
    }
}

private struct ExploreView: View {
    @State private var calendar = EconomicCalendarViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    economicCalendarHeader
                    economicCalendarFilters

                    if calendar.isLoading {
                        ProgressView("Loading high impact events")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if calendar.groupedEvents.isEmpty {
                        ContentUnavailableView(
                            "No High Impact Events",
                            systemImage: "folder.badge.questionmark",
                            description: Text(calendar.errorMessage ?? "Try changing filters or check back later.")
                        )
                        .padding(.top, 32)
                    } else {
                        ForEach(calendar.groupedEvents, id: \.0) { day, events in
                            EconomicCalendarDaySection(day: day, events: events)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Explore")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await calendar.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await calendar.load()
            }
        }
    }

    private var economicCalendarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Economic Calendar")
                        .font(.title2.bold())
                    Text("High impact red-folder events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var economicCalendarFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Date", selection: $calendar.dateFilter) {
                ForEach(EconomicCalendarDateFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Upcoming only", isOn: $calendar.upcomingOnly)
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    currencyChip("All", isSelected: calendar.selectedCurrencies.isEmpty) {
                        calendar.selectedCurrencies.removeAll()
                    }
                    ForEach(calendar.currencies, id: \.self) { currency in
                        currencyChip(currency, isSelected: calendar.selectedCurrencies.contains(currency)) {
                            calendar.toggleCurrency(currency)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func currencyChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(isSelected ? Color.red : Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct EconomicCalendarDaySection: View {
    let day: Date
    let events: [EconomicEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.chartLabel)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                headerRow
                ForEach(events) { event in
                    NavigationLink {
                        EconomicEventDetailView(event: event)
                    } label: {
                        EconomicEventRow(event: event)
                    }
                    .buttonStyle(.plain)

                    if event.id != events.last?.id {
                        Divider().padding(.leading, 74)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Time").frame(width: 50, alignment: .leading)
            Text("Cur").frame(width: 38, alignment: .leading)
            Text("Event").frame(maxWidth: .infinity, alignment: .leading)
            Text("F").frame(width: 45, alignment: .trailing)
            Text("P").frame(width: 45, alignment: .trailing)
            Text("A").frame(width: 45, alignment: .trailing)
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct EconomicEventRow: View {
    let event: EconomicEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(event.timestampUtc.intradayChartLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(event.currency)
                .font(.caption.bold())
                .frame(width: 38, alignment: .leading)

            Image(systemName: "folder.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .frame(width: 16)

            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            valueText(event.forecast)
            valueText(event.previous)
            valueText(event.actual)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func valueText(_ value: String?) -> some View {
        Text(value ?? "-")
            .font(.caption.monospacedDigit())
            .foregroundStyle(value == nil ? Color.secondary.opacity(0.6) : Color.primary)
            .frame(width: 45, alignment: .trailing)
    }
}

private struct EconomicEventDetailView: View {
    let event: EconomicEvent

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.red)
                        Text(event.currency)
                            .font(.headline.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    }
                    Text(event.title)
                        .font(.title2.bold())
                    Text(event.timestampUtc.crosshairIntradayLabel)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Release") {
                detailRow("Date", event.date)
                detailRow("Time", event.time)
                detailRow("Forecast", event.forecast)
                detailRow("Previous", event.previous)
                detailRow("Actual", event.actual)
                detailRow("Revised", event.revised)
                detailRow("Source", event.source)
            }

            if let description = event.description, !description.isEmpty {
                Section("Description") {
                    Text(description)
                }
            }
        }
        .navigationTitle("Event Details")
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "-")
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct BacktestView: View {
    @Bindable var store: MarketStore
    @Bindable var paperTrading: PaperTradingService
    @State private var strategy: StrategyKind = .movingAverageCross
    @State private var fastPeriod = 12.0
    @State private var slowPeriod = 26.0

    var result: BacktestResult {
        BacktestEngine.run(
            candles: store.candles,
            strategy: strategy,
            fastPeriod: Int(fastPeriod),
            slowPeriod: Int(slowPeriod)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    backtestHeader
                    PaperTradingPanel(store: store, paperTrading: paperTrading)
                    strategyControls
                    PerformanceCards(result: result)
                    EquityCurve(points: result.equity)
                        .frame(height: 220)
                        .padding(.horizontal)
                    TradeList(trades: result.trades)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color.black)
            .navigationTitle("Backtest")
        }
    }

    private var backtestHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(store.selected.ticker)
                    .font(.largeTitle.bold())
                Text("Backtesting · Paper Trading · Simulated only")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.title)
                .foregroundStyle(.cyan)
        }
        .padding(.horizontal)
    }

    private var strategyControls: some View {
        VStack(spacing: 14) {
            Picker("Strategy", selection: $strategy) {
                ForEach(StrategyKind.allCases) { strategy in
                    Text(strategy.rawValue).tag(strategy)
                }
            }
            .pickerStyle(.segmented)

            slider("Fast MA", value: $fastPeriod, range: 5...30)
            slider("Slow MA", value: $slowPeriod, range: 18...80)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                Spacer()
                Text(Int(value.wrappedValue), format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}

private struct PaperTradingPanel: View {
    @Bindable var store: MarketStore
    @Bindable var paperTrading: PaperTradingService

    private var latestCandle: Candle? {
        store.candles.last
    }

    private var estimatedRiskPerShare: Double {
        guard paperTrading.ticketStopLoss > 0 else { return 0 }
        return abs((paperTrading.ticketOrderType == .market ? latestCandle?.close ?? paperTrading.ticketEntryPrice : paperTrading.ticketEntryPrice) - paperTrading.ticketStopLoss)
    }

    private var estimatedRewardPerShare: Double {
        guard paperTrading.ticketTakeProfit > 0 else { return 0 }
        return abs(paperTrading.ticketTakeProfit - (paperTrading.ticketOrderType == .market ? latestCandle?.close ?? paperTrading.ticketEntryPrice : paperTrading.ticketEntryPrice))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paper Trading")
                        .font(.title2.bold())
                    Text("No real money. No real orders. This is simulated paper trading only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset") {
                    paperTrading.resetAccount()
                }
                .font(.caption.bold())
                .foregroundStyle(.red)
            }

            accountSummary
            orderTicket
            chartPlacementToggle
            positionsAndOrders
            PaperStatsView(stats: paperTrading.stats)
            PaperTradeHistoryView(trades: paperTrading.account.closedTrades)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
        .onAppear {
            syncTicketDefaults()
            paperTrading.configureInstrument(store.selected)
            paperTrading.processVisibleCandles(store.candles, symbol: store.selected.ticker)
        }
        .onChange(of: store.selected.ticker) { _, _ in
            syncTicketDefaults()
            paperTrading.configureInstrument(store.selected)
        }
        .onChange(of: store.selected.last) { _, _ in
            syncTicketDefaults()
        }
    }

    private var accountSummary: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                paperMetric("Equity", paperTrading.account.equity.moneyText, paperTrading.account.equity >= paperTrading.account.startingBalance ? .green : .red)
                paperMetric("Cash", paperTrading.account.cashBalance.moneyText, .primary)
            }
            GridRow {
                paperMetric("Buying Power", paperTrading.account.buyingPower.moneyText, .cyan)
                paperMetric("Open P/L", paperTrading.account.unrealizedPL.signedMoneyText, paperTrading.account.unrealizedPL >= 0 ? .green : .red)
            }
        }
    }

    private var orderTicket: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Direction", selection: $paperTrading.ticketDirection) {
                    ForEach(TradeDirection.allCases) { direction in
                        Text(direction.shortLabel).tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Type", selection: $paperTrading.ticketOrderType) {
                    ForEach(SimulatedOrderType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }

            HStack(spacing: 10) {
                ticketNumberField("Qty", value: $paperTrading.ticketQuantity)
                ticketNumberField("Entry", value: $paperTrading.ticketEntryPrice, disabled: paperTrading.ticketOrderType == .market)
            }

            HStack(spacing: 10) {
                ticketNumberField("Stop", value: $paperTrading.ticketStopLoss)
                ticketNumberField("Target", value: $paperTrading.ticketTakeProfit)
            }

            HStack(spacing: 10) {
                ticketNumberField("Risk $", value: $paperTrading.ticketRiskAmount)
                ticketNumberField("Risk %", value: $paperTrading.ticketRiskPercent)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Est. risk \(estimatedRiskPerShare.moneyText)/share")
                    Text("Est. reward \(estimatedRewardPerShare.moneyText)/share")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    if paperTrading.ticketOrderType == .market {
                        paperTrading.ticketEntryPrice = latestCandle?.close ?? paperTrading.ticketEntryPrice
                    }
                    _ = paperTrading.submitOrder(symbol: store.selected.ticker, latestCandle: latestCandle)
                } label: {
                    Text("Submit Simulated Order")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(paperTrading.ticketDirection == .long ? .green : .red, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chartPlacementToggle: some View {
        Toggle(isOn: $paperTrading.chartPlacementEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chart tap mode")
                    .font(.subheadline.bold())
                Text("Use the Paper Trade toolbar icon, then tap a price level to place the current ticket.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private var positionsAndOrders: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open Positions")
                .font(.headline)
            if paperTrading.account.openPositions.isEmpty {
                Text("No open paper positions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paperTrading.account.openPositions) { position in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(position.symbol) \(position.direction.shortLabel) \(position.quantityText)")
                                .font(.subheadline.bold())
                            Text("Entry \(position.entryPrice.priceText) · Last \(position.lastPrice.priceText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(position.unrealizedPL.signedMoneyText)
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(position.unrealizedPL >= 0 ? .green : .red)
                            Button("Close") {
                                paperTrading.closePosition(position, at: latestCandle?.close ?? position.lastPrice, time: latestCandle?.date ?? Date(), barIndex: latestCandle?.index ?? position.entryBarIndex)
                            }
                            .font(.caption.bold())
                        }
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Text("Pending Orders")
                .font(.headline)
                .padding(.top, 4)
            if paperTrading.account.pendingOrders.isEmpty {
                Text("No pending orders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paperTrading.account.pendingOrders) { order in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(order.symbol) \(order.direction.shortLabel) \(order.type.rawValue)")
                                .font(.subheadline.bold())
                            Text("\(order.quantity, specifier: "%.0f") @ \(order.entryPrice.priceText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Cancel") {
                            paperTrading.cancelOrder(order)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func paperMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func ticketNumberField(_ title: String, value: Binding<Double>, disabled: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad)
                .disabled(disabled)
                .font(.subheadline.monospacedDigit())
                .padding(9)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .opacity(disabled ? 0.52 : 1)
        }
    }

    private func syncTicketDefaults() {
        let price = latestCandle?.close ?? store.selected.last
        guard price > 0 else { return }
        if paperTrading.ticketEntryPrice == 0 {
            paperTrading.ticketEntryPrice = price
        }
        if paperTrading.ticketStopLoss == 0 {
            paperTrading.ticketStopLoss = price * 0.99
        }
        if paperTrading.ticketTakeProfit == 0 {
            paperTrading.ticketTakeProfit = price * 1.02
        }
    }
}

private struct PaperStatsView: View {
    let stats: PaperTradingStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance")
                .font(.headline)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    metric("Trades", "\(stats.totalTrades)", .primary)
                    metric("Win Rate", "\(String(format: "%.0f", stats.winRate))%", .primary)
                    metric("Net", stats.netProfit.signedMoneyText, stats.netProfit >= 0 ? .green : .red)
                }
                GridRow {
                    metric("Avg Win", stats.averageWin.moneyText, .green)
                    metric("Avg Loss", stats.averageLoss.signedMoneyText, .red)
                    metric("PF", String(format: "%.2f", stats.profitFactor), .cyan)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PaperTradeHistoryView: View {
    let trades: [SimulatedTrade]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trade History")
                .font(.headline)

            if trades.isEmpty {
                Text("Closed paper trades will show here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trades.prefix(12)) { trade in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(trade.symbol) \(trade.direction.shortLabel) · \(trade.exitReason.rawValue)")
                                .font(.subheadline.bold())
                            Text("\(trade.entryTime.crosshairIntradayLabel) -> \(trade.exitTime.crosshairIntradayLabel) · \(trade.entryPrice.priceText) -> \(trade.exitPrice.priceText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(trade.profitLoss.signedMoneyText)
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(trade.profitLoss >= 0 ? .green : .red)
                            Text(trade.percentReturn.percentText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

private struct PerformanceCards: View {
    let result: BacktestResult

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                metric("Return", result.totalReturn.percentText, result.totalReturn >= 0 ? .green : .red)
                metric("Win Rate", "\(String(format: "%.0f", result.winRate))%", .primary)
            }
            GridRow {
                metric("Drawdown", "\(String(format: "%.1f", result.maxDrawdown))%", .red)
                metric("Sharpe", String(format: "%.2f", result.sharpe), .primary)
            }
        }
        .padding(.horizontal)
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct EquityCurve: View {
    let points: [EquityPoint]

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Bar", point.index), y: .value("Equity", point.value))
                .foregroundStyle(.cyan.opacity(0.22))
            LineMark(x: .value("Bar", point.index), y: .value("Equity", point.value))
                .foregroundStyle(.cyan)
                .lineStyle(StrokeStyle(lineWidth: 2.4))
        }
        .chartXAxis(.hidden)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct TradeList: View {
    let trades: [Trade]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trades")
                .font(.headline)

            if trades.isEmpty {
                ContentUnavailableView("No Trades", systemImage: "tray", description: Text("Try a different strategy or period."))
            } else {
                ForEach(trades.prefix(8)) { trade in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Bars \(trade.entryIndex)-\(trade.exitIndex)")
                                .font(.subheadline.bold())
                            Text("\(trade.entry.priceText) -> \(trade.exit.priceText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(trade.profitPercent.percentText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(trade.profitPercent >= 0 ? .green : .red)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

private struct StrategyLibraryView: View {
    @Bindable var store: MarketStore
    @Bindable var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var canvasExpanded = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let user = auth.currentUser {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.email)
                                .font(.headline)
                            Text(user.isEmailVerified ? "Email verified" : "Email not verified")
                                .font(.caption)
                                .foregroundStyle(user.isEmailVerified ? .green : .orange)
                        }
                    }

                    Button {
                        auth.enableFaceID()
                    } label: {
                        Label("Enable Face ID", systemImage: "faceid")
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $canvasExpanded) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 12)], spacing: 12) {
                            ForEach(ChartBackgroundTheme.allCases) { theme in
                                canvasSwatch(theme)
                            }
                        }
                        .padding(.vertical, 8)
                    } label: {
                        HStack {
                            Label("Canvas", systemImage: "paintpalette")
                            Spacer()
                            Text(store.chartBackgroundTheme.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                        dismiss()
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Menu")
        }
    }

    private func canvasSwatch(_ theme: ChartBackgroundTheme) -> some View {
        Button {
            store.selectChartBackground(theme)
        } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: theme.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                store.chartBackgroundTheme == theme ? Color.cyan : Color.white.opacity(0.18),
                                lineWidth: store.chartBackgroundTheme == theme ? 2.5 : 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if store.chartBackgroundTheme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.cyan, .black)
                                .padding(5)
                        }
                    }

                Text(theme.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.rawValue) canvas")
    }
}

private struct TabBarVisibilityController: UIViewControllerRepresentable {
    let hidden: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        VisibilityViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? VisibilityViewController)?.setTabBarHidden(hidden)
    }

    private final class VisibilityViewController: UIViewController {
        private var pendingHidden = false

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyVisibility()
        }

        func setTabBarHidden(_ hidden: Bool) {
            pendingHidden = hidden
            applyVisibility()
            DispatchQueue.main.async { [weak self] in
                self?.applyVisibility()
            }
        }

        private func applyVisibility() {
            guard let tabController = nearestTabBarController() else { return }
            tabController.tabBar.isHidden = pendingHidden
            tabController.tabBar.alpha = pendingHidden ? 0 : 1
            tabController.tabBar.isUserInteractionEnabled = !pendingHidden
        }

        private func nearestTabBarController() -> UITabBarController? {
            var current: UIViewController? = self
            while let controller = current {
                if let tabController = controller as? UITabBarController {
                    return tabController
                }
                if let tabController = controller.tabBarController {
                    return tabController
                }
                current = controller.parent
            }
            return nil
        }
    }
}

#Preview {
    ContentView(auth: AuthService())
}
