"use strict";

/**
 * Applies neon/schema.sql using DATABASE_URL or POSTGRES_* from the environment.
 * Usage:
 *   vercel env pull .env.vercel.apply --environment=production --yes
 *   node scripts/apply-neon-schema.cjs .env.vercel.apply
 * Or with env already exported: node scripts/apply-neon-schema.cjs
 */
const fs = require("fs");
const path = require("path");
const { Client } = require("pg");

function loadDotEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    console.error("File not found:", filePath);
    process.exit(1);
  }
  const text = fs.readFileSync(filePath, "utf8");
  for (const line of text.split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#")) {
      continue;
    }
    const eq = t.indexOf("=");
    if (eq === -1) {
      continue;
    }
    const key = t.slice(0, eq).trim();
    let val = t.slice(eq + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (process.env[key] === undefined) {
      process.env[key] = val;
    }
  }
}

function getDatabaseUrl() {
  const candidates = [
    process.env.DATABASE_URL,
    process.env.POSTGRES_URL,
    process.env.POSTGRES_PRISMA_URL,
    process.env.POSTGRES_URL_NON_POOLING,
  ];
  for (const c of candidates) {
    const s = String(c || "").trim();
    if (s) {
      return s;
    }
  }
  return "";
}

function splitStatements(sql) {
  const noComments = sql
    .split("\n")
    .filter((line) => !/^\s*--/.test(line))
    .join("\n");
  return noComments
    .split(";")
    .map((s) => s.trim())
    .filter(Boolean);
}

async function main() {
  const envFile = process.argv[2];
  if (envFile) {
    loadDotEnvFile(path.resolve(envFile));
  }

  const connectionString = getDatabaseUrl();
  if (!connectionString) {
    console.error("No DATABASE_URL or POSTGRES_URL in environment.");
    process.exit(1);
  }

  const schemaPath = path.join(__dirname, "..", "neon", "schema.sql");
  const sql = fs.readFileSync(schemaPath, "utf8");
  const statements = splitStatements(sql);

  const useSsl = !/localhost|127\.0\.0\.1/i.test(connectionString);
  const client = new Client({
    connectionString,
    ssl: useSsl ? { rejectUnauthorized: false } : false,
  });

  await client.connect();
  try {
    for (const stmt of statements) {
      await client.query(stmt);
      console.log("OK:", stmt.split(/\s+/).slice(0, 4).join(" "), "…");
    }
  } finally {
    await client.end();
  }
  console.log("Schema applied.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
