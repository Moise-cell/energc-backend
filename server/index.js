require('dotenv').config();
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const { Pool } = require('pg');
const app = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || 'esp32_secret_key';

const pool = new Pool({
  host: process.env.NEON_HOST,
  port: process.env.NEON_PORT,
  database: process.env.NEON_DATABASE,
  user: process.env.NEON_USER,
  password: process.env.NEON_PASSWORD,
  ssl: { rejectUnauthorized: false }
});

app.use(cors());
app.use(express.json());

// Endpoint de santé
app.get('/api/health', (req, res) => {
  res.status(200).json({ status: 'OK', timestamp: new Date().toISOString() });
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
  const { deviceId, energy } = req.body;
  
  // Validation des données
  if (!deviceId || typeof energy !== 'number') {
    return res.status(400).json({ 
      error: 'Données invalides',
      message: 'deviceId et energy sont requis. energy doit être un nombre.'
    });
  }

  try {
    // Vérifier si la maison existe
    const maison = await pool.query(
      'SELECT * FROM maisons WHERE device_id = $1',
      [deviceId]
    );

    if (maison.rows.length === 0) {
      return res.status(404).json({
        error: 'Maison non trouvée',
        message: 'Cette maison n\'est pas enregistrée dans le système.'
      });
    }

    // Insérer la mesure
    await pool.query(
      'INSERT INTO mesures (device_id, energy1, created_at) VALUES ($1, $2, NOW())',
      [deviceId, energy]
    );

    res.status(200).json({ 
      message: 'Données enregistrées',
      deviceId: deviceId,
      energy: energy,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('Erreur lors de l\'insertion:', err);
    res.status(500).json({ 
      error: 'Erreur lors de l\'insertion en base',
      details: err.message 
    });
  }
});

// Endpoint pour enregistrer une nouvelle maison
app.post('/api/maisons', checkApiKey, async (req, res) => {
  const { deviceId, nom, adresse } = req.body;

  if (!deviceId || !nom) {
    return res.status(400).json({
      error: 'Données invalides',
      message: 'deviceId et nom sont requis.'
    });
  }

  try {
    const result = await pool.query(
      'INSERT INTO maisons (device_id, nom, adresse) VALUES ($1, $2, $3) RETURNING *',
      [deviceId, nom, adresse]
    );

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Erreur lors de l\'insertion:', err);
    res.status(500).json({
      error: 'Erreur lors de l\'insertion',
      details: err.message
    });
  }
});

// Endpoint pour obtenir les données d'une maison
app.get('/api/maisons/:deviceId', checkApiKey, async (req, res) => {
  const { deviceId } = req.params;

  try {
    const maison = await pool.query(
      'SELECT * FROM maisons WHERE device_id = $1',
      [deviceId]
    );

    if (maison.rows.length === 0) {
      return res.status(404).json({
        error: 'Maison non trouvée'
      });
    }

    // Récupérer les dernières mesures
    const mesures = await pool.query(
      'SELECT * FROM mesures WHERE device_id = $1 ORDER BY created_at DESC LIMIT 10',
      [deviceId]
    );

    res.status(200).json({
      maison: maison.rows[0],
      mesures: mesures.rows
    });
  } catch (err) {
    console.error('Erreur lors de la récupération:', err);
    res.status(500).json({
      error: 'Erreur lors de la récupération',
      details: err.message
    });
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

app.listen(PORT, () => {
  console.log(`Serveur démarré sur le port ${PORT}`);
}); 