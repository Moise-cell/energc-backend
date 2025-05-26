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

async function checkTables() {
  try {
    // Vérifier la structure de la table mesures
    console.log('\nStructure de la table mesures :');
    const mesuresColumns = await pool.query(`
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_name = 'mesures'
      ORDER BY ordinal_position;
    `);
    mesuresColumns.rows.forEach(col => {
      console.log(`- ${col.column_name}: ${col.data_type} (${col.is_nullable === 'YES' ? 'nullable' : 'not null'})`);
    });

    // Vérifier la structure de la table utilisateurs
    console.log('\nStructure de la table utilisateurs :');
    const usersColumns = await pool.query(`
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_name = 'utilisateurs'
      ORDER BY ordinal_position;
    `);
    usersColumns.rows.forEach(col => {
      console.log(`- ${col.column_name}: ${col.data_type} (${col.is_nullable === 'YES' ? 'nullable' : 'not null'})`);
    });

    // Compter le nombre d'enregistrements
    const mesuresCount = await pool.query('SELECT COUNT(*) FROM mesures');
    const usersCount = await pool.query('SELECT COUNT(*) FROM utilisateurs');
    
    console.log('\nNombre d\'enregistrements :');
    console.log(`- mesures: ${mesuresCount.rows[0].count}`);
    console.log(`- utilisateurs: ${usersCount.rows[0].count}`);

  } catch (error) {
    console.error('❌ Erreur:', error.message);
  } finally {
    await pool.end();
  }
}

checkTables(); 