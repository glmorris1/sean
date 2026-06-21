const markets = [
  { symbol: "SEANUSD", name: "Sean Composite", price: 142.38, change: 2.84, volume: "18.2M" },
  { symbol: "AAPL", name: "Apple Inc.", price: 201.22, change: 0.74, volume: "48.1M" },
  { symbol: "NVDA", name: "NVIDIA Corp.", price: 168.44, change: -1.21, volume: "62.8M" },
  { symbol: "BTCUSD", name: "Bitcoin", price: 64642.12, change: 1.48, volume: "31.4B" },
  { symbol: "ETHUSD", name: "Ethereum", price: 3184.8, change: -0.36, volume: "14.7B" },
  { symbol: "PIXEL", name: "Pixelware Labs", price: 87.94, change: -2.18, volume: "4.9M" },
  { symbol: "SPY", name: "S&P 500 ETF", price: 612.22, change: 0.28, volume: "71.5M" },
  { symbol: "GLD", name: "Gold Trust", price: 231.42, change: 0.42, volume: "9.8M" }
];

const state = {
  active: markets[0],
  frame: "1D",
  volatility: 5,
  candles: []
};

const els = {
  shell: document.querySelector(".app-shell"),
  marketList: document.querySelector("#marketList"),
  search: document.querySelector("#symbolSearch"),
  chart: document.querySelector("#priceChart"),
  spark: document.querySelector("#sparkChart"),
  activeSymbol: document.querySelector("#activeSymbol"),
  activeName: document.querySelector("#activeName"),
  chartTitle: document.querySelector("#chartTitle"),
  chartSubtitle: document.querySelector("#chartSubtitle"),
  lastPrice: document.querySelector("#lastPrice"),
  lastChange: document.querySelector("#lastChange"),
  detailsSymbol: document.querySelector("#detailsSymbol"),
  statOpen: document.querySelector("#statOpen"),
  statHigh: document.querySelector("#statHigh"),
  statLow: document.querySelector("#statLow"),
  statVolume: document.querySelector("#statVolume"),
  limitPrice: document.querySelector("#limitPrice"),
  volatility: document.querySelector("#volatility")
};

function money(value) {
  if (value > 1000) return value.toLocaleString("en-US", { maximumFractionDigits: 2 });
  return value.toFixed(2);
}

function seededNoise(seed) {
  const x = Math.sin(seed) * 10000;
  return x - Math.floor(x);
}

function buildCandles(market, frame = state.frame, volatility = state.volatility) {
  const count = frame === "1D" ? 86 : frame === "1W" ? 74 : frame === "1M" ? 68 : frame === "3M" ? 58 : 52;
  const base = market.price / (1 + market.change / 100);
  let cursor = base;
  const seedBase = market.symbol.split("").reduce((sum, char) => sum + char.charCodeAt(0), 0) + frame.length * 19;
  return Array.from({ length: count }, (_, index) => {
    const drift = market.change / 100 / count;
    const wave = Math.sin(index / 5 + seedBase) * volatility * 0.12;
    const noise = (seededNoise(seedBase + index * 7) - 0.45) * volatility * 0.55;
    const open = cursor;
    const close = Math.max(1, open * (1 + drift + (wave + noise) / 100));
    const spread = Math.abs(close - open) + market.price * (0.004 + seededNoise(seedBase + index) * 0.014);
    const high = Math.max(open, close) + spread * (0.45 + seededNoise(seedBase + index * 3));
    const low = Math.min(open, close) - spread * (0.35 + seededNoise(seedBase + index * 5));
    cursor = close;
    return { open, high, low, close };
  });
}

function fitCanvas(canvas) {
  const rect = canvas.getBoundingClientRect();
  const ratio = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.floor(rect.width * ratio));
  canvas.height = Math.max(1, Math.floor(rect.height * ratio));
  const ctx = canvas.getContext("2d");
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
  return { ctx, width: rect.width, height: rect.height };
}

function cssVar(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() ||
    getComputedStyle(els.shell).getPropertyValue(name).trim();
}

function drawChart() {
  const { ctx, width, height } = fitCanvas(els.chart);
  const candles = state.candles;
  const pad = { top: 12, right: 58, bottom: 28, left: 18 };
  const values = candles.flatMap((candle) => [candle.high, candle.low]);
  const max = Math.max(...values);
  const min = Math.min(...values);
  const scale = (value) => pad.top + ((max - value) / (max - min)) * (height - pad.top - pad.bottom);
  const plotWidth = width - pad.left - pad.right;
  const slot = plotWidth / candles.length;
  const green = cssVar("--green");
  const red = cssVar("--red");
  const muted = cssVar("--muted");
  const line = cssVar("--line");

  ctx.clearRect(0, 0, width, height);
  ctx.font = "12px Inter, system-ui, sans-serif";
  ctx.strokeStyle = line;
  ctx.fillStyle = muted;

  for (let i = 0; i < 5; i += 1) {
    const y = pad.top + i * ((height - pad.top - pad.bottom) / 4);
    ctx.beginPath();
    ctx.moveTo(pad.left, y);
    ctx.lineTo(width - pad.right + 20, y);
    ctx.stroke();
    const label = max - i * ((max - min) / 4);
    ctx.fillText(money(label), width - pad.right + 26, y + 4);
  }

  candles.forEach((candle, index) => {
    const x = pad.left + index * slot + slot / 2;
    const openY = scale(candle.open);
    const closeY = scale(candle.close);
    const highY = scale(candle.high);
    const lowY = scale(candle.low);
    const up = candle.close >= candle.open;
    ctx.strokeStyle = up ? green : red;
    ctx.fillStyle = up ? green : red;
    ctx.beginPath();
    ctx.moveTo(x, highY);
    ctx.lineTo(x, lowY);
    ctx.stroke();
    const bodyTop = Math.min(openY, closeY);
    const bodyHeight = Math.max(2, Math.abs(closeY - openY));
    ctx.fillRect(x - Math.max(3, slot * 0.28), bodyTop, Math.max(4, slot * 0.56), bodyHeight);
  });

  const last = candles.at(-1).close;
  const lastY = scale(last);
  ctx.strokeStyle = cssVar("--cyan");
  ctx.setLineDash([5, 5]);
  ctx.beginPath();
  ctx.moveTo(pad.left, lastY);
  ctx.lineTo(width - pad.right + 18, lastY);
  ctx.stroke();
  ctx.setLineDash([]);
}

function drawSpark() {
  const { ctx, width, height } = fitCanvas(els.spark);
  const closes = state.candles.map((candle) => candle.close);
  const max = Math.max(...closes);
  const min = Math.min(...closes);
  const xStep = width / Math.max(1, closes.length - 1);
  const y = (value) => 16 + ((max - value) / (max - min)) * (height - 32);

  ctx.clearRect(0, 0, width, height);
  ctx.strokeStyle = cssVar("--cyan");
  ctx.lineWidth = 2;
  ctx.beginPath();
  closes.forEach((close, index) => {
    const x = index * xStep;
    if (index === 0) ctx.moveTo(x, y(close));
    else ctx.lineTo(x, y(close));
  });
  ctx.stroke();

  const gradient = ctx.createLinearGradient(0, 0, 0, height);
  gradient.addColorStop(0, "rgba(84, 182, 255, 0.28)");
  gradient.addColorStop(1, "rgba(84, 182, 255, 0)");
  ctx.lineTo(width, height);
  ctx.lineTo(0, height);
  ctx.closePath();
  ctx.fillStyle = gradient;
  ctx.fill();
}

function renderMarkets(filter = "") {
  const visible = markets.filter((market) =>
    `${market.symbol} ${market.name}`.toLowerCase().includes(filter.toLowerCase())
  );
  els.marketList.innerHTML = visible.map((market) => `
    <button class="market-row ${market.symbol === state.active.symbol ? "active" : ""}" type="button" data-symbol="${market.symbol}">
      <span>
        <strong>${market.symbol}</strong>
        <span>${market.name}</span>
      </span>
      <span class="price-stack">
        <strong>${money(market.price)}</strong>
        <span class="${market.change >= 0 ? "positive" : "negative"}">${market.change >= 0 ? "+" : ""}${market.change.toFixed(2)}%</span>
      </span>
    </button>
  `).join("");
}

function updateQuote() {
  state.candles = buildCandles(state.active);
  const first = state.candles[0];
  const high = Math.max(...state.candles.map((candle) => candle.high));
  const low = Math.min(...state.candles.map((candle) => candle.low));
  const last = state.candles.at(-1).close;
  const change = ((last - first.open) / first.open) * 100;
  const changeClass = change >= 0 ? "positive" : "negative";

  els.activeSymbol.textContent = state.active.symbol;
  els.activeName.textContent = state.active.name;
  els.chartTitle.textContent = state.active.symbol;
  els.chartSubtitle.textContent = `${state.active.name} · Sean Exchange`;
  els.lastPrice.textContent = money(last);
  els.lastChange.textContent = `${change >= 0 ? "+" : ""}${change.toFixed(2)}%`;
  els.lastChange.className = changeClass;
  els.detailsSymbol.textContent = state.active.symbol;
  els.statOpen.textContent = money(first.open);
  els.statHigh.textContent = money(high);
  els.statLow.textContent = money(low);
  els.statVolume.textContent = state.active.volume;
  els.limitPrice.value = last.toFixed(2);
  renderMarkets(els.search.value);
  drawChart();
  drawSpark();
}

function bindEvents() {
  els.marketList.addEventListener("click", (event) => {
    const row = event.target.closest(".market-row");
    if (!row) return;
    state.active = markets.find((market) => market.symbol === row.dataset.symbol) || state.active;
    updateQuote();
  });

  els.search.addEventListener("input", () => renderMarkets(els.search.value));

  document.querySelector("#timeframes").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-frame]");
    if (!button) return;
    state.frame = button.dataset.frame;
    document.querySelectorAll("#timeframes button").forEach((item) => item.classList.toggle("selected", item === button));
    updateQuote();
  });

  document.querySelectorAll(".tool").forEach((tool) => {
    tool.addEventListener("click", () => {
      document.querySelectorAll(".tool").forEach((item) => item.classList.toggle("active", item === tool));
    });
  });

  document.querySelector("#themeToggle").addEventListener("click", () => {
    const next = els.shell.dataset.theme === "dark" ? "light" : "dark";
    els.shell.dataset.theme = next;
    drawChart();
    drawSpark();
  });

  document.querySelector("#reloadChart").addEventListener("click", updateQuote);

  els.volatility.addEventListener("input", () => {
    state.volatility = Number(els.volatility.value);
    updateQuote();
  });

  window.addEventListener("resize", () => {
    drawChart();
    drawSpark();
  });
}

document.addEventListener("DOMContentLoaded", () => {
  if (window.lucide) window.lucide.createIcons();
  bindEvents();
  updateQuote();
  setInterval(() => {
    const jitter = (Math.random() - 0.48) * state.active.price * 0.001;
    state.active.price = Math.max(1, state.active.price + jitter);
    updateQuote();
  }, 7000);
});
