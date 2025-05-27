require('dotenv').config();
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const { Pool } = require('pg');
const app = express();
const PORT = process.env.PORT || 30000;
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

// Middleware pour vérifier l'API key
const checkApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  if (!apiKey || apiKey !== API_KEY) {
    return res.status(401).json({ error: 'API key invalide' });
  }
  next();
};

// Fonction pour charger les commandes depuis le fichier
const loadCommands = () => {
  try {
    if (fs.existsSync('commands.json')) {
      const data = fs.readFileSync('commands.json', 'utf8');
      return JSON.parse(data);
    }
    return { commands: [] };
  } catch (error) {
    console.error('Erreur lors du chargement des commandes:', error);
    return { commands: [] };
  }
};

// Fonction pour sauvegarder les commandes dans le fichier
const saveCommands = (commands) => {
  try {
    fs.writeFileSync('commands.json', JSON.stringify(commands, null, 2));
  } catch (error) {
    console.error('Erreur lors de la sauvegarde des commandes:', error);
  }
};

// Endpoint pour récupérer les commandes
app.get('/api/commands', checkApiKey, (req, res) => {
  const deviceId = req.query.deviceId;
  const commands = loadCommands();
  
  if (deviceId) {
    commands.commands = commands.commands.filter(cmd => cmd.device_id === deviceId);
  }
  
  res.json(commands);
});

// Endpoint pour ajouter une commande de recharge
app.post('/api/commands', checkApiKey, async (req, res) => {
  try {
    console.log('Headers reçus:', req.headers);
    console.log('Body brut reçu:', req.body);
    console.log('Type de body:', typeof req.body);
    
    const { device_id, command_type, parameters, timestamp } = req.body;
    
    console.log('Données extraites:', {
      device_id,
      command_type,
      parameters,
      timestamp,
      device_id_type: typeof device_id,
      command_type_type: typeof command_type,
      parameters_type: typeof parameters,
      timestamp_type: typeof timestamp
    });
    
    // Vérification des champs requis
    if (!device_id) {
      console.log('Erreur: device_id manquant');
      return res.status(400).json({ error: 'device_id est requis' });
    }
    if (!command_type) {
      console.log('Erreur: command_type manquant');
      return res.status(400).json({ error: 'command_type est requis' });
    }
    
    // Vérification spécifique pour les commandes de recharge
    if (command_type === 'recharge_energy') {
      if (!parameters) {
        console.log('Erreur: parameters manquant pour recharge_energy');
        return res.status(400).json({ error: 'parameters est requis pour la commande recharge_energy' });
      }
      if (typeof parameters.energy_amount !== 'number') {
        console.log('Erreur: energy_amount doit être un nombre, reçu:', parameters.energy_amount);
        return res.status(400).json({ error: 'energy_amount doit être un nombre' });
      }
    }
    
    const commands = loadCommands();
    const newCommand = {
      device_id,
      command_type,
      parameters: parameters || {},
      timestamp: timestamp || new Date().toISOString(),
      status: 'pending'
    };
    
    console.log('Nouvelle commande créée:', newCommand);
    
    commands.commands.push(newCommand);
    saveCommands(commands);
    
    res.status(201).json(newCommand);
  } catch (error) {
    console.error('Erreur lors de l\'ajout de la commande:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Endpoint pour confirmer l'exécution d'une commande
app.post('/api/commands/confirm', checkApiKey, (req, res) => {
  try {
    const { device_id, command_id } = req.body;
    const commands = loadCommands();
    
    const command = commands.commands.find(cmd => 
      cmd.device_id === device_id && cmd.timestamp === command_id
    );
    
    if (command) {
      command.status = 'executed';
      saveCommands(commands);
      res.json({ message: 'Commande confirmée' });
    } else {
      res.status(404).json({ error: 'Commande non trouvée' });
    }
  } catch (error) {
    console.error('Erreur lors de la confirmation de la commande:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Endpoint pour recevoir les données de l'ESP32
app.post('/api/data', checkApiKey, async (req, res) => {
  // Accepte energy OU energy1/energy2
  const { deviceId, voltage, current1, current2, energy, energy1, energy2, relay1Status, relay2Status, timestamp } = req.body;

  // Validation : au moins deviceId et une valeur d'énergie
  if (!deviceId || typeof voltage !== 'number' || typeof current1 !== 'number' || typeof current2 !== 'number') {
    return res.status(400).json({ error: 'Données invalides', message: 'Champs obligatoires manquants.' });
  }
  if (energy === undefined && (energy1 === undefined || energy2 === undefined)) {
    return res.status(400).json({ error: 'Données invalides', message: 'energy ou energy1/energy2 requis.' });
  }

  // Si energy1/energy2 absents, utilise energy pour les deux
  const e1 = energy1 !== undefined ? energy1 : energy;
  const e2 = energy2 !== undefined ? energy2 : energy;

  try {
    await pool.query(
      'INSERT INTO mesures (device_id, voltage, current1, current2, energy1, energy2, relay1_status, relay2_status, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)',
      [
        deviceId,
        voltage,
        current1,
        current2,
        e1,
        e2,
        relay1Status ?? false,
        relay2Status ?? false,
        timestamp ?? new Date().toISOString()
      ]
    );
    res.status(200).json({ message: 'Données enregistrées' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Erreur lors de l\'insertion en base' });
  }
});

// Récupérer les dernières données d'un device
app.get('/api/data/:deviceId/latest', checkApiKey, async (req, res) => {
  const { deviceId } = req.params;
  try {
    const result = await pool.query(
      'SELECT device_id, voltage, current1, current2, energy1, energy2, relay1_status, relay2_status, created_at FROM mesures WHERE device_id = $1 ORDER BY created_at DESC LIMIT 1',
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