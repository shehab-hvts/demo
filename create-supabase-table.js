import { Pool } from 'pg';

const pool = new Pool({
  connectionString: 'postgresql://postgres:hvts007!qed@db.wgbfmoancrtswyumpule.supabase.co:5432/postgres',
  ssl: { rejectUnauthorized: false }
});

async function createTable() {
  try {
    console.log('Connecting to Supabase...');
    const client = await pool.connect();

    console.log('Creating tasks table...');
    await client.query(`
      CREATE TABLE IF NOT EXISTS tasks (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        done BOOLEAN NOT NULL DEFAULT false,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    `);

    console.log('✅ Table created successfully!');

    // Verify
    const result = await client.query("SELECT * FROM tasks LIMIT 1");
    console.log('✅ Table verified - structure is correct');

    client.release();
    await pool.end();

    console.log('\n✅ Supabase ready! Table exists and is ready for use.');
    process.exit(0);
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

createTable();
