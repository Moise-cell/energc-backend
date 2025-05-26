require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: 'ep-holy-smoke-a2rsvccb-pooler.eu-central-1.aws.neon.tech',
  port: 5432,
  database: 'neondb',
  user: 'neondb_owner',
  password: 'npg_kpLoWY25fmGV',
  ssl: {
    rejectUnauthorized: false,
    sslmode: 'require'
  }
});

async function testConnection() {
  try {
    // Test de connexion
    const result = await pool.query('SELECT NOW()');
    console.log('✅ Connexion à la base de données réussie:', result.rows[0].now);

    // Vérifier les tables
    const tables = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public'
    `);
    console.log('\nTables existantes :');
    tables.rows.forEach(table => console.log(`- ${table.table_name}`));

  } catch (error) {
    console.error('❌ Erreur de connexion:', error.message);
    console.error('Détails de la configuration :', {
      host: pool.options.host,
      port: pool.options.port,
      database: pool.options.database,
      user: pool.options.user
    });
  } finally {
    await pool.end();
  }
}

testConnection(); 