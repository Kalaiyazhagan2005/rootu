import fs from 'fs';
import path from 'path';
import { Pool } from 'pg';
import { config } from '../config/env';

export async function runMigrations() {
  const databaseUrl = config.database.url;

  if (!databaseUrl) {
    console.error('DATABASE_URL is not configured in .env or environment variables.');
    console.log('Example: DATABASE_URL="postgresql://postgres:your_password@localhost:5432/rootu_dev"');
    process.exit(1);
  }

  console.log(`[RootU Migration] Connecting to PostgreSQL database...`);
  const pool = new Pool({ connectionString: databaseUrl });

  try {
    const client = await pool.connect();
    console.log('[RootU Migration] Connected successfully.');

    const sqlPath = path.join(__dirname, 'migrations', '001_initial_schema.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');

    console.log('[RootU Migration] Executing 001_initial_schema.sql...');
    await client.query(sql);
    console.log('[RootU Migration] All tables and indexes created successfully!');

    client.release();
    await pool.end();
  } catch (err: any) {
    console.error('[RootU Migration Error]:', err.message || err);
    await pool.end();
    process.exit(1);
  }
}

if (require.main === module) {
  runMigrations();
}

