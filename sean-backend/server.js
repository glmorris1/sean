import cors from "cors";
import crypto from "node:crypto";
import express from "express";
import fs from "node:fs/promises";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import { createRemoteJWKSet, jwtVerify } from "jose";
import nodemailer from "nodemailer";
import path from "node:path";
import pg from "pg";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.join(__dirname, "data");
const dbPath = path.join(dataDir, "db.json");
const { Pool } = pg;

const app = express();
const port = Number(process.env.PORT || 8787);
const isProduction = process.env.NODE_ENV === "production";
const hasPostgres = Boolean(process.env.DATABASE_URL);
const firebaseProjectID = process.env.FIREBASE_PROJECT_ID || "";
const allowDevelopmentCodes = process.env.ALLOW_DEVELOPMENT_CODES === "true" || !isProduction;
const corsOrigins = String(process.env.CORS_ORIGINS || "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

if (isProduction && !process.env.APP_SECRET) {
  console.error("APP_SECRET is required when NODE_ENV=production.");
  process.exit(1);
}

if (isProduction && !hasPostgres) {
  console.error("DATABASE_URL is required when NODE_ENV=production.");
  process.exit(1);
}

app.set("trust proxy", 1);
app.use(helmet());
app.use(cors({
  origin(origin, callback) {
    if (!origin || corsOrigins.length === 0 || corsOrigins.includes(origin)) {
      callback(null, true);
      return;
    }
    callback(new Error("Origin not allowed"));
  }
}));
app.use(express.json({ limit: "2mb" }));
app.use(rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 300,
  standardHeaders: true,
  legacyHeaders: false
}));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false
});

const dbPool = hasPostgres ? new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: isProduction ? { rejectUnauthorized: false } : undefined
}) : null;
const firebaseJWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com")
);

const emptyDb = {
  usersByEmail: {},
  usersByToken: {},
  snapshotsByUserID: {}
};

const defaultTimeframes = ["15s", "1m", "2m", "3m", "5m", "10m", "15m", "30m", "1h", "4h", "1d"];
const symbolCatalog = [
  {
    symbol: "XAUUSD",
    displayName: "Gold / U.S. Dollar",
    assetType: "spot_metal",
    baseAsset: "XAU",
    quoteAsset: "USD",
    exchange: "OTC",
    provider: "OANDA",
    providerSymbol: "XAU_USD",
    yahooFallbackSymbol: "GC=F",
    tickSize: 0.01,
    pipSize: 0.01,
    contractSize: null,
    availableTimeframes: defaultTimeframes
  },
  {
    symbol: "XAGUSD",
    displayName: "Silver / U.S. Dollar",
    assetType: "spot_metal",
    baseAsset: "XAG",
    quoteAsset: "USD",
    exchange: "OTC",
    provider: "OANDA",
    providerSymbol: "XAG_USD",
    yahooFallbackSymbol: "SI=F",
    tickSize: 0.001,
    pipSize: 0.001,
    contractSize: null,
    availableTimeframes: defaultTimeframes
  },
  {
    symbol: "EURUSD",
    displayName: "Euro / U.S. Dollar",
    assetType: "forex",
    baseAsset: "EUR",
    quoteAsset: "USD",
    exchange: "OTC",
    provider: "OANDA",
    providerSymbol: "EUR_USD",
    yahooFallbackSymbol: "EURUSD=X",
    tickSize: 0.00001,
    pipSize: 0.0001,
    contractSize: null,
    availableTimeframes: defaultTimeframes
  },
  {
    symbol: "GBPUSD",
    displayName: "British Pound / U.S. Dollar",
    assetType: "forex",
    baseAsset: "GBP",
    quoteAsset: "USD",
    exchange: "OTC",
    provider: "OANDA",
    providerSymbol: "GBP_USD",
    yahooFallbackSymbol: "GBPUSD=X",
    tickSize: 0.00001,
    pipSize: 0.0001,
    contractSize: null,
    availableTimeframes: defaultTimeframes
  },
  {
    symbol: "USDJPY",
    displayName: "U.S. Dollar / Japanese Yen",
    assetType: "forex",
    baseAsset: "USD",
    quoteAsset: "JPY",
    exchange: "OTC",
    provider: "OANDA",
    providerSymbol: "USD_JPY",
    yahooFallbackSymbol: "JPY=X",
    tickSize: 0.001,
    pipSize: 0.01,
    contractSize: null,
    availableTimeframes: defaultTimeframes
  },
  {
    symbol: "MES1!",
    displayName: "Micro E-mini S&P 500 Futures Continuous Contract, Front Month",
    assetType: "futures",
    baseAsset: "MES",
    quoteAsset: "USD",
    exchange: "CME",
    provider: "GhostTrade Market Data",
    providerSymbol: "MES=F",
    yahooFallbackSymbol: "MES=F",
    tickSize: 0.25,
    pipSize: null,
    contractSize: 5,
    availableTimeframes: defaultTimeframes
  }
];

function findCatalogSymbol(symbol) {
  const normalized = String(symbol || "").trim().toUpperCase();
  return symbolCatalog.find((item) => item.symbol.toUpperCase() === normalized);
}

function searchCatalog(query) {
  const normalized = String(query || "").trim().toUpperCase();
  const lower = String(query || "").trim().toLowerCase();
  if (!normalized) return [];
  return symbolCatalog.filter((item) => (
    item.symbol.toUpperCase().includes(normalized) ||
    item.displayName.toLowerCase().includes(lower) ||
    item.assetType.toLowerCase().includes(lower) ||
    item.baseAsset.toUpperCase().includes(normalized) ||
    item.quoteAsset.toUpperCase().includes(normalized) ||
    item.providerSymbol.toUpperCase().includes(normalized) ||
    (lower === "gold" && item.baseAsset === "XAU") ||
    (lower === "silver" && item.baseAsset === "XAG") ||
    (lower === "metals" && item.assetType === "spot_metal")
  ));
}

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function makeID() {
  return crypto.randomUUID();
}

function makeCode() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, "0");
}

function makeToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function hashToken(token) {
  return crypto.createHash("sha256").update(String(token || "")).digest("base64url");
}

function hashPassword(password, salt = crypto.randomBytes(16).toString("base64url")) {
  const hash = crypto.scryptSync(password, salt, 64).toString("base64url");
  return `${salt}:${hash}`;
}

function verifyPassword(password, storedHash) {
  const [salt] = String(storedHash || "").split(":");
  if (!salt) return false;
  const candidate = Buffer.from(hashPassword(password, salt));
  const stored = Buffer.from(storedHash);
  if (candidate.length !== stored.length) return false;
  return crypto.timingSafeEqual(
    candidate,
    stored
  );
}

function makeVerificationExpiry() {
  return new Date(Date.now() + 15 * 60 * 1000).toISOString();
}

async function loadDb() {
  try {
    const raw = await fs.readFile(dbPath, "utf8");
    return { ...emptyDb, ...JSON.parse(raw) };
  } catch {
    return structuredClone(emptyDb);
  }
}

async function saveDb(db) {
  await fs.mkdir(dataDir, { recursive: true });
  await fs.writeFile(dbPath, JSON.stringify(db, null, 2));
}

async function initPostgres() {
  if (!dbPool) return;
  await dbPool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      is_email_verified BOOLEAN NOT NULL DEFAULT FALSE,
      verification_code TEXT,
      verification_expires_at TIMESTAMPTZ,
      auth_token_hash TEXT UNIQUE NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS user_snapshots (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      snapshot JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

function rowToUser(row, authToken = null) {
  if (!row) return null;
  return {
    id: row.id,
    email: row.email,
    passwordHash: row.password_hash,
    isEmailVerified: Boolean(row.is_email_verified),
    verificationCode: row.verification_code,
    verificationExpiresAt: row.verification_expires_at ? new Date(row.verification_expires_at).toISOString() : null,
    authToken,
    authTokenHash: row.auth_token_hash,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null,
    updatedAt: row.updated_at ? new Date(row.updated_at).toISOString() : null
  };
}

async function findUserByEmail(email) {
  if (dbPool) {
    const result = await dbPool.query("SELECT * FROM users WHERE email = $1", [email]);
    return rowToUser(result.rows[0]);
  }
  const db = await loadDb();
  return db.usersByEmail[email] || null;
}

async function findUserByToken(token) {
  if (dbPool) {
    const result = await dbPool.query("SELECT * FROM users WHERE auth_token_hash = $1", [hashToken(token)]);
    return rowToUser(result.rows[0], token);
  }
  const db = await loadDb();
  const userID = db.usersByToken[token];
  return Object.values(db.usersByEmail).find((candidate) => candidate.id === userID) || null;
}

async function verifyFirebaseUser(token) {
  if (!firebaseProjectID) return null;
  const { payload } = await jwtVerify(token, firebaseJWKS, {
    issuer: `https://securetoken.google.com/${firebaseProjectID}`,
    audience: firebaseProjectID
  });
  if (!payload.sub || !payload.email || payload.email_verified !== true) {
    return null;
  }
  const user = {
    id: `firebase:${payload.sub}`,
    email: normalizeEmail(payload.email),
    passwordHash: "firebase",
    isEmailVerified: true,
    verificationCode: null,
    verificationExpiresAt: null,
    authToken: null,
    authTokenHash: `firebase:${payload.sub}`,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString()
  };
  await upsertUser(user);
  return user;
}

async function upsertUser(user) {
  if (dbPool) {
    await dbPool.query(
      `INSERT INTO users (
        id, email, password_hash, is_email_verified, verification_code,
        verification_expires_at, auth_token_hash, created_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, COALESCE($8::timestamptz, NOW()), NOW())
      ON CONFLICT (email) DO UPDATE SET
        password_hash = EXCLUDED.password_hash,
        is_email_verified = EXCLUDED.is_email_verified,
        verification_code = EXCLUDED.verification_code,
        verification_expires_at = EXCLUDED.verification_expires_at,
        auth_token_hash = EXCLUDED.auth_token_hash,
        updated_at = NOW()`,
      [
        user.id,
        user.email,
        user.passwordHash,
        user.isEmailVerified,
        user.verificationCode || null,
        user.verificationExpiresAt || null,
        user.authTokenHash || hashToken(user.authToken),
        user.createdAt || null
      ]
    );
    return;
  }

  const db = await loadDb();
  db.usersByEmail[user.email] = user;
  if (user.authToken) {
    db.usersByToken[user.authToken] = user.id;
  }
  await saveDb(db);
}

async function getSnapshot(userID) {
  if (dbPool) {
    const result = await dbPool.query("SELECT snapshot FROM user_snapshots WHERE user_id = $1", [userID]);
    return result.rows[0]?.snapshot || null;
  }
  const db = await loadDb();
  return db.snapshotsByUserID[userID] || null;
}

async function saveSnapshot(userID, body) {
  const snapshot = {
    watchlist: Array.isArray(body.watchlist) ? body.watchlist : [],
    paperTradingAccount: body.paperTradingAccount || {},
    updatedAt: new Date().toISOString()
  };
  if (dbPool) {
    await dbPool.query(
      `INSERT INTO user_snapshots (user_id, snapshot, updated_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (user_id) DO UPDATE SET snapshot = EXCLUDED.snapshot, updated_at = NOW()`,
      [userID, snapshot]
    );
    return snapshot;
  }
  const db = await loadDb();
  db.snapshotsByUserID[userID] = snapshot;
  await saveDb(db);
  return snapshot;
}

function publicUser(user, extra = {}) {
  return {
    id: user.id,
    email: user.email,
    isEmailVerified: user.isEmailVerified,
    authToken: user.authToken || extra.authToken,
    ...extra
  };
}

function yahooInterval(timeframe) {
  switch (String(timeframe || "1d").toLowerCase()) {
    case "1m":
    case "2m":
    case "5m":
    case "15m":
    case "30m":
      return String(timeframe).toLowerCase();
    case "3m":
    case "10m":
      return "1m";
    case "1h":
    case "4h":
      return "60m";
    case "1 day":
    case "1d":
    default:
      return "1d";
  }
}

function yahooRange(timeframe) {
  switch (String(timeframe || "1d").toLowerCase()) {
    case "1m":
    case "3m":
    case "10m":
      return "8d";
    case "2m":
    case "5m":
    case "15m":
    case "30m":
      return "60d";
    case "1h":
    case "4h":
      return "2y";
    case "1 day":
    case "1d":
    default:
      return "40y";
  }
}

function bucketSeconds(timeframe) {
  switch (String(timeframe || "").toLowerCase()) {
    case "3m": return 3 * 60;
    case "10m": return 10 * 60;
    case "4h": return 4 * 60 * 60;
    default: return 0;
  }
}

function normalizeCandles(rows, timeframe) {
  const sorted = rows
    .filter((row) => Number.isFinite(row.open) && Number.isFinite(row.high) && Number.isFinite(row.low) && Number.isFinite(row.close))
    .sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
  const seconds = bucketSeconds(timeframe);
  if (!seconds) return sorted;

  const buckets = new Map();
  for (const row of sorted) {
    const millis = new Date(row.timestamp).getTime();
    const bucketStart = Math.floor(millis / 1000 / seconds) * seconds * 1000;
    const key = new Date(bucketStart).toISOString();
    const existing = buckets.get(key);
    if (!existing) {
      buckets.set(key, { ...row, timestamp: key });
      continue;
    }
    existing.high = Math.max(existing.high, row.high);
    existing.low = Math.min(existing.low, row.low);
    existing.close = row.close;
    existing.volume += row.volume || 0;
  }
  return Array.from(buckets.values()).sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
}

function oandaGranularity(timeframe) {
  switch (String(timeframe || "1d").toLowerCase()) {
    case "15s": return "S15";
    case "1m": return "M1";
    case "2m": return "M2";
    case "3m": return "M3";
    case "5m": return "M5";
    case "10m": return "M10";
    case "15m": return "M15";
    case "30m": return "M30";
    case "1h": return "H1";
    case "4h": return "H4";
    case "1 day":
    case "1d":
    default:
      return "D";
  }
}

function shouldUseOanda(catalogSymbol) {
  return ["spot_metal", "forex"].includes(catalogSymbol.assetType) &&
    catalogSymbol.provider === "OANDA" &&
    Boolean(catalogSymbol.providerSymbol);
}

function oandaStartDate(timeframe) {
  const now = Date.now();
  const day = 24 * 60 * 60 * 1000;
  switch (String(timeframe || "1d").toLowerCase()) {
    case "15s":
    case "1m":
    case "2m":
    case "3m":
    case "5m":
    case "10m":
      return new Date(now - 30 * day);
    case "15m":
    case "30m":
      return new Date(now - 180 * day);
    case "1h":
    case "4h":
      return new Date(now - 5 * 365 * day);
    case "1 day":
    case "1d":
    default:
      return new Date("2005-01-01T00:00:00Z");
  }
}

async function fetchOandaCandles(catalogSymbol, timeframe) {
  const token = process.env.OANDA_API_TOKEN;
  if (!token || !shouldUseOanda(catalogSymbol)) return null;

  const baseURL = String(process.env.OANDA_API_URL || "https://api-fxpractice.oanda.com").replace(/\/+$/, "");
  const start = Number.isFinite(Date.parse(process.env.OANDA_HISTORY_START || ""))
    ? new Date(process.env.OANDA_HISTORY_START)
    : oandaStartDate(timeframe);
  let cursor = new Date();
  const rows = [];
  const seen = new Set();
  const maxCandles = Math.min(Number(process.env.OANDA_MAX_CANDLES || 50000), 500000);
  let requests = 0;

  while (rows.length < maxCandles && cursor > start && requests < 25) {
    requests += 1;
    const url = new URL(`${baseURL}/v3/instruments/${encodeURIComponent(catalogSymbol.providerSymbol)}/candles`);
    url.searchParams.set("price", "M");
    url.searchParams.set("granularity", oandaGranularity(timeframe));
    url.searchParams.set("count", String(Math.min(5000, maxCandles - rows.length)));
    url.searchParams.set("to", cursor.toISOString());
    url.searchParams.set("includeFirst", "true");

    const response = await fetch(url, {
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${token}`
      }
    });
    if (!response.ok) {
      throw new Error(`OANDA returned ${response.status}`);
    }

    const payload = await response.json();
    const candles = Array.isArray(payload?.candles) ? payload.candles : [];
    if (!candles.length) break;

    for (const candle of candles) {
      const mid = candle.mid;
      if (!mid || !candle.time || seen.has(candle.time)) continue;
      seen.add(candle.time);
      rows.push({
        symbol: catalogSymbol.symbol,
        exchange: catalogSymbol.exchange,
        timeframe,
        timestamp: new Date(candle.time).toISOString(),
        open: Number(mid.o),
        high: Number(mid.h),
        low: Number(mid.l),
        close: Number(mid.c),
        volume: Number(candle.volume || 0)
      });
    }

    const firstTime = new Date(candles[0].time);
    if (!Number.isFinite(firstTime.getTime()) || firstTime >= cursor) break;
    cursor = new Date(firstTime.getTime() - 1);

    if (firstTime <= start) break;
  }

  const normalized = normalizeCandles(rows, timeframe)
    .filter((row) => new Date(row.timestamp) >= start);
  return normalized.length ? normalized : null;
}

async function fetchYahooCandles(catalogSymbol, timeframe) {
  const providerSymbol = catalogSymbol.yahooFallbackSymbol || catalogSymbol.providerSymbol || catalogSymbol.symbol;
  const encodedSymbol = encodeURIComponent(providerSymbol);
  const url = new URL(`https://query1.finance.yahoo.com/v8/finance/chart/${encodedSymbol}`);
  url.searchParams.set("range", yahooRange(timeframe));
  url.searchParams.set("interval", yahooInterval(timeframe));
  url.searchParams.set("includePrePost", "true");
  url.searchParams.set("events", "history");

  const response = await fetch(url, {
    headers: {
      Accept: "application/json",
      "User-Agent": "Mozilla/5.0"
    }
  });
  if (!response.ok) {
    throw new Error(`Yahoo returned ${response.status}`);
  }
  const payload = await response.json();
  const result = payload?.chart?.result?.[0];
  const quote = result?.indicators?.quote?.[0];
  if (!result?.timestamp?.length || !quote) {
    throw new Error(payload?.chart?.error?.description || "No candles returned");
  }

  const rows = result.timestamp.map((timestamp, index) => ({
    symbol: catalogSymbol.symbol,
    exchange: catalogSymbol.exchange,
    timeframe,
    timestamp: new Date(timestamp * 1000).toISOString(),
    open: quote.open?.[index],
    high: quote.high?.[index],
    low: quote.low?.[index],
    close: quote.close?.[index],
    volume: Number(quote.volume?.[index] || 0)
  }));
  return normalizeCandles(rows, timeframe);
}

async function fetchTwelveDataCandles(catalogSymbol, timeframe) {
  if (!process.env.TWELVE_DATA_API_KEY) return null;
  const intervalMap = {
    "1m": "1min",
    "2m": "1min",
    "3m": "1min",
    "5m": "5min",
    "10m": "5min",
    "15m": "15min",
    "30m": "30min",
    "1h": "1h",
    "4h": "4h",
    "1 day": "1day",
    "1d": "1day"
  };
  const url = new URL("https://api.twelvedata.com/time_series");
  url.searchParams.set("symbol", catalogSymbol.providerSymbol);
  url.searchParams.set("interval", intervalMap[String(timeframe || "1d").toLowerCase()] || "1day");
  url.searchParams.set("outputsize", "5000");
  url.searchParams.set("timezone", "UTC");
  url.searchParams.set("apikey", process.env.TWELVE_DATA_API_KEY);

  const response = await fetch(url, { headers: { Accept: "application/json" } });
  if (!response.ok) return null;
  const payload = await response.json();
  if (payload?.status === "error" || !Array.isArray(payload?.values)) return null;
  const rows = payload.values.map((value) => ({
    symbol: catalogSymbol.symbol,
    exchange: catalogSymbol.exchange,
    timeframe,
    timestamp: new Date(`${value.datetime.replace(" ", "T")}Z`).toISOString(),
    open: Number(value.open),
    high: Number(value.high),
    low: Number(value.low),
    close: Number(value.close),
    volume: Number(value.volume || 0)
  }));
  return normalizeCandles(rows, timeframe);
}

async function fetchMarketCandles(catalogSymbol, timeframe) {
  try {
    const oandaRows = await fetchOandaCandles(catalogSymbol, timeframe);
    if (oandaRows?.length) return oandaRows;
  } catch (error) {
    console.warn(`[market-data] OANDA failed for ${catalogSymbol.symbol}: ${error.message}`);
  }

  const twelveDataRows = await fetchTwelveDataCandles(catalogSymbol, timeframe);
  if (twelveDataRows?.length) return twelveDataRows;
  return fetchYahooCandles(catalogSymbol, timeframe);
}

function smtpConfigured() {
  return Boolean(process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS);
}

if (isProduction && !smtpConfigured() && !firebaseProjectID) {
  console.error("Configure either FIREBASE_PROJECT_ID or SMTP_HOST/SMTP_USER/SMTP_PASS when NODE_ENV=production.");
  process.exit(1);
}

function createTransport() {
  if (!smtpConfigured()) return null;
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: String(process.env.SMTP_SECURE || "false") === "true",
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS
    }
  });
}

async function sendVerificationEmail(email, code) {
  const transport = createTransport();
  if (!transport) {
    if (!allowDevelopmentCodes) {
      throw new Error("Email delivery is not configured.");
    }
    console.log(`[GhostTrade auth dev] Verification code for ${email}: ${code}`);
    return { mode: "development", code };
  }

  await transport.sendMail({
    from: process.env.SMTP_FROM || "GhostTrade <no-reply@ghosttrade.local>",
    to: email,
    subject: "Your GhostTrade verification code",
    text: `Your GhostTrade verification code is ${code}.`,
    html: `
      <div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;line-height:1.45">
        <h2>Verify your GhostTrade account</h2>
        <p>Your verification code is:</p>
        <p style="font-size:28px;font-weight:800;letter-spacing:4px">${code}</p>
        <p>This code lets you finish signing in to GhostTrade.</p>
      </div>
    `
  });

  return { mode: "email" };
}

function requireAuth(req, res, next) {
  const token = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!token) {
    res.status(401).json({ error: "Missing token" });
    return;
  }
  findUserByToken(token)
    .then(async (user) => {
      if (!user) {
        user = await verifyFirebaseUser(token);
      }
      if (!user || !user.isEmailVerified) {
        res.status(401).json({ error: "Invalid token" });
        return;
      }
      req.user = user;
      next();
    })
    .catch(next);
}

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    environment: isProduction ? "production" : "development",
    storage: dbPool ? "postgres" : "json-file",
    emailDelivery: firebaseProjectID ? "firebase" : (smtpConfigured() ? "smtp" : "development-code"),
    developmentCodesEnabled: allowDevelopmentCodes && !smtpConfigured()
  });
});

app.get("/symbols/search", (req, res) => {
  const results = searchCatalog(req.query.q).map(({ yahooFallbackSymbol, ...symbol }) => symbol);
  res.json(results);
});

app.get("/candles", async (req, res, next) => {
  try {
    const symbol = String(req.query.symbol || "").trim().toUpperCase();
    const timeframe = String(req.query.timeframe || "1d").trim();
    const limit = Math.min(Number(req.query.limit || 500000), 500000);
    const catalogSymbol = findCatalogSymbol(symbol) || {
      symbol,
      displayName: symbol,
      assetType: String(req.query.assetType || "stocks"),
      baseAsset: symbol.slice(0, 3),
      quoteAsset: symbol.slice(-3),
      exchange: String(req.query.exchange || "US"),
      provider: "Yahoo Finance",
      providerSymbol: symbol,
      yahooFallbackSymbol: symbol,
      tickSize: 0.01,
      pipSize: null,
      contractSize: null,
      availableTimeframes: defaultTimeframes
    };

    const candles = await fetchMarketCandles(catalogSymbol, timeframe);
    res.json(candles.slice(-limit));
  } catch (error) {
    next(error);
  }
});

app.post("/auth/register", authLimiter, async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body.email);
    const password = String(req.body.password || "");
    if (!isValidEmail(email)) {
      res.status(400).json({ error: "Invalid email" });
      return;
    }
    if (password.length < 8) {
      res.status(400).json({ error: "Password must be at least 8 characters" });
      return;
    }

    const existing = await findUserByEmail(email);
    if (existing?.isEmailVerified) {
      res.status(409).json({ error: "Account already exists" });
      return;
    }

    const code = makeCode();
    const authToken = makeToken();
    const user = {
      id: existing?.id || makeID(),
      email,
      passwordHash: hashPassword(password),
      isEmailVerified: false,
      verificationCode: code,
      verificationExpiresAt: makeVerificationExpiry(),
      authToken,
      authTokenHash: hashToken(authToken),
      createdAt: existing?.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    await upsertUser(user);

    const delivery = await sendVerificationEmail(email, code);
    res.json(publicUser(user, {
      verificationDeliveryMode: delivery.mode,
      developmentVerificationCode: delivery.code || null
    }));
  } catch (error) {
    next(error);
  }
});

app.post("/auth/login", authLimiter, async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body.email);
    const password = String(req.body.password || "");
    const user = await findUserByEmail(email);
    if (!user || !verifyPassword(password, user.passwordHash)) {
      res.status(401).json({ error: "Invalid credentials" });
      return;
    }
    const authToken = makeToken();
    user.authToken = authToken;
    user.authTokenHash = hashToken(authToken);
    user.updatedAt = new Date().toISOString();
    await upsertUser(user);
    res.json(publicUser(user));
  } catch (error) {
    next(error);
  }
});

app.post("/auth/verification/resend", authLimiter, async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body.email);
    const user = await findUserByEmail(email);
    if (!user) {
      res.status(404).json({ error: "Unknown account" });
      return;
    }
    user.verificationCode = makeCode();
    user.verificationExpiresAt = makeVerificationExpiry();
    user.updatedAt = new Date().toISOString();
    await upsertUser(user);
    const delivery = await sendVerificationEmail(email, user.verificationCode);
    res.json({
      verificationDeliveryMode: delivery.mode,
      developmentVerificationCode: delivery.code || null
    });
  } catch (error) {
    next(error);
  }
});

app.post("/auth/verify-email", authLimiter, async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body.email);
    const code = String(req.body.code || "").trim();
    const user = await findUserByEmail(email);
    if (!user || user.verificationCode !== code) {
      res.status(400).json({ error: "Invalid verification code" });
      return;
    }
    if (user.verificationExpiresAt && new Date(user.verificationExpiresAt).getTime() < Date.now()) {
      res.status(400).json({ error: "Verification code expired" });
      return;
    }

    user.isEmailVerified = true;
    user.verificationCode = null;
    user.verificationExpiresAt = null;
    user.authToken = makeToken();
    user.authTokenHash = hashToken(user.authToken);
    user.updatedAt = new Date().toISOString();
    await upsertUser(user);
    res.json(publicUser(user));
  } catch (error) {
    next(error);
  }
});

app.get("/user-data", requireAuth, async (req, res, next) => {
  try {
  const snapshot = await getSnapshot(req.user.id);
  if (!snapshot) {
    res.status(404).json({ error: "No saved workspace" });
    return;
  }
  res.json(snapshot);
  } catch (error) {
    next(error);
  }
});

app.put("/user-data", requireAuth, async (req, res, next) => {
  try {
    await saveSnapshot(req.user.id, req.body);
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ error: "Server error" });
});

await initPostgres();

app.listen(port, "0.0.0.0", () => {
  console.log(`GhostTrade auth backend listening on http://0.0.0.0:${port}`);
  console.log(`Storage: ${dbPool ? "Postgres" : "JSON file"}`);
  console.log(`Email delivery: ${smtpConfigured() ? "SMTP" : "development codes in server log"}`);
});
