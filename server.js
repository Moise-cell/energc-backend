require('dotenv').config();
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const { Pool } = require('pg');
const app = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || 'esp32_secret_key';

// Configuration CORS pour Render
app.use(cors({
  origin: process.env.FRONTEND_URL || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'x-api-key']
}));

// Vérification des variables d'environnement requises
const requiredEnvVars = ['NEON_HOST', 'NEON_PORT', 'NEON_DATABASE', 'NEON_USER', 'NEON_PASSWORD'];
const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar]);

if (missingEnvVars.length > 0) {
  console.error('Variables d\'environnement manquantes:', missingEnvVars.join(', '));
  process.exit(1);
}

const pool = new Pool({
  host: process.env.NEON_HOST,
  port: process.env.NEON_PORT,
  database: process.env.NEON_DATABASE,
  user: process.env.NEON_USER,
  password: process.env.NEON_PASSWORD,
  ssl: { rejectUnauthorized: false }
});

// Test de la connexion à la base de données
pool.connect()
  .then(() => console.log('Connexion à la base de données réussie'))
  .catch(err => {
    console.error('Erreur de connexion à la base de données:', err);
    process.exit(1);
  });

app.use(express.json());

// Endpoint de test pour le navigateur
app.get('/test/mesures', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM mesures ORDER BY created_at DESC LIMIT 10');
    res.status(200).json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erreur lors de la récupération des données' });
  }
});

app.get('/test/utilisateurs', async (req, res) => {
  try {
    const result = await pool.query('SELECT id, username, user_type FROM utilisateurs');
    res.status(200).json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erreur lors de la récupération des utilisateurs' });
  }
});

const COMMANDS_FILE = './commands.json';

// Utilitaire pour charger/sauver les commandes
function loadCommands() {
  if (!fs.existsSync(COMMANDS_FILE)) return [];
  return JSON.parse(fs.readFileSync(COMMANDS_FILE, 'utf8'));
}
function saveCommands(commands) {
  fs.writeFileSync(COMMANDS_FILE, JSON.stringify(commands, null, 2));
}

// Middleware d'authentification simple
function checkApiKey(req, res, next) {
  const key = req.headers['x-api-key'];
  if (key !== API_KEY) return res.status(401).json({ error: 'Unauthorized' });
  next();
}

// Endpoint pour recevoir les données de l'ESP32
app.post('/api/data', checkApiKey, async (req, res) => {
  const { deviceId, voltage, current1, current2, energy1, energy2 } = req.body;
  if (!deviceId || typeof voltage !== 'number' || typeof current1 !== 'number' || typeof current2 !== 'number' || typeof energy1 !== 'number' || typeof energy2 !== 'number') {
    return res.status(400).json({ error: 'Données invalides' });
  }
  try {
    await pool.query(
      'INSERT INTO mesures (device_id, voltage, current1, current2, energy1, energy2, created_at) VALUES ($1, $2, $3, $4, $5, $6, NOW())',
      [deviceId, voltage, current1, current2, energy1, energy2]
    );
    res.status(200).json({ message: 'Données enregistrées' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erreur lors de l\'insertion en base' });
  }
});

// Endpoint pour ajouter une commande
app.post('/api/commands', checkApiKey, (req, res) => {
  const { command } = req.body;
  if (!command) {
    return res.status(400).json({ error: 'Commande manquante' });
  }
  let commands = loadCommands();
  commands.push(command);
  saveCommands(commands);
  res.status(201).json({ message: 'Commande ajoutée' });
});

// Endpoint pour récupérer les commandes en attente
app.get('/api/commands', checkApiKey, (req, res) => {
  let commands = loadCommands();
  res.status(200).json({ commands });
  saveCommands([]); // Vider après récupération
});

// Récupérer les dernières données d'un device
app.get('/api/data/:deviceId/latest', checkApiKey, async (req, res) => {
  const { deviceId } = req.params;
  try {
    const result = await pool.query(
      'SELECT * FROM mesures WHERE device_id = $1 ORDER BY created_at DESC LIMIT 1',
      [deviceId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Aucune donnée trouvée' });
    }
    res.status(200).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erreur lors de la récupération des données' });
  }
});

// Endpoint pour l'authentification des utilisateurs
app.post('/api/login', checkApiKey, async (req, res) => {
  const { username, password } = req.body;
  try {
    const result = await pool.query(
      'SELECT * FROM utilisateurs WHERE username = $1 AND password = $2',
      [username, password]
    );
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Identifiants invalides' });
    }
    res.status(200).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erreur lors de l\'authentification' });
  }
});

// Gestion des erreurs globales
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Erreur serveur' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Serveur démarré sur le port ${PORT}`);
});