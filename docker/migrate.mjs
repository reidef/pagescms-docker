// Applies upstream's Drizzle migrations (db/migrations) to DATABASE_URL.
//
// Upstream runs migrations with drizzle-kit, a dev dependency we don't ship.
// drizzle-orm's runtime migrator reads the same journal and tracking table, so
// databases migrated either way are interchangeable.
//
// A Postgres advisory lock serialises concurrent runs, so it is safe for every
// replica to run this on start-up.
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { fileURLToPath } from "node:url";

const LOCK_ID = 7_232_374_797; // arbitrary, fixed for this app

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("[migrate] DATABASE_URL is not set");
  process.exit(1);
}

// One connection, so the advisory lock and the migration share a session.
const sql = postgres(url, { max: 1, onnotice: () => {} });

try {
  console.log("[migrate] waiting for migration lock");
  await sql`select pg_advisory_lock(${LOCK_ID}::bigint)`;
  console.log("[migrate] applying migrations");
  await migrate(drizzle(sql), {
    migrationsFolder: fileURLToPath(new URL("../db/migrations", import.meta.url)),
  });
  await sql`select pg_advisory_unlock(${LOCK_ID}::bigint)`;
  console.log("[migrate] done");
} catch (err) {
  console.error("[migrate] failed:", err);
  process.exitCode = 1;
} finally {
  await sql.end({ timeout: 5 });
}
