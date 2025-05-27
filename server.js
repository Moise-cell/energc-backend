require('dotenv').config();
const express = require('express');
const cors = require('cors');
const fs = require('fs'); // Note: L'utilisation de fs pour commands.json est éphémère sur Render.com
const { Pool } = require('pg');
const app = express();
const PORT = process.env.PORT || 30000;
const API_KEY = process.env.API_KEY || 'esp32_secret_key';

// Configuration CORS pour Render
app.use(cors({
  origin: process.env.FRONTEND_URL || '*', // Permet toutes les origines si FRONTEND_URL n'est pas défini
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'x-api-key']
}));

// Vérification des variables d'environnement requises
const requiredEnvVars = ['NEON_HOST', 'NEON_PORT', 'NEON_DATABASE', 'NEON_USER', 'NEON_PASSWORD'];
const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar]);

if (missingEnvVars.length > 0) {
  console.error('Variables d\'environnement manquantes:', missingEnvVars.join(', '));
  process.exit(1); // Arrête l'application si des variables essentielles sont manquantes
}

// Configuration du pool de connexion PostgreSQL
const pool = new Pool({
  host: process.env.NEON_HOST,
  port: process.env.NEON_PORT,
  database: process.env.NEON_DATABASE,
  user: process.env.NEON_USER,
  password: process.env.NEON_PASSWORD,
  ssl: { rejectUnauthorized: false } // Nécessaire pour les connexions SSL à Neon
});

// Test de la connexion à la base de données au démarrage
pool.connect()
  .then(() => console.log('Connexion à la base de données réussie'))
  .catch(err => {
    console.error('Erreur de connexion à la base de données:', err);
    process.exit(1); // Arrête l'application si la connexion DB échoue
  });

// Middleware pour parser le JSON des requêtes entrantes
app.use(express.json());

// --- Endpoints de Test (pour le navigateur, sans API key) ---
// Récupérer les 10 dernières mesures
app.get('/test/mesures', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM mesures ORDER BY created_at DESC LIMIT 10');
    res.status(200).json(result.rows);
  } catch (err) {
    console.error('Erreur /test/mesures:', err);
    res.status(500).json({ error: 'Erreur lors de la récupération des données de test' });
  }
});

// Récupérer la liste des utilisateurs de test
app.get('/test/utilisateurs', async (req, res) => {
  try {
    const result = await pool.query('SELECT id, username, user_type FROM utilisateurs');
    res.status(200).json(result.rows);
  } catch (err) {
    console.error('Erreur /test/utilisateurs:', err);
    res.status(500).json({ error: 'Erreur lors de la récupération des utilisateurs de test' });
  }
});

// --- Middleware de Vérification de l'API Key ---
const checkApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  console.log('API_KEY attendue:', API_KEY, '| API_KEY reçue:', apiKey);
  if (!apiKey || apiKey !== API_KEY) {
    return res.status(401).json({ error: 'API key invalide' });
  }
  next(); // Passe au prochain middleware ou à la route handler
};

// --- Fonctions de Gestion des Commandes (via fichier commands.json - Éphémère sur Render) ---
// Charge les commandes depuis un fichier JSON local
const loadCommands = () => {
  try {
    if (fs.existsSync('commands.json')) {
      const data = fs.readFileSync('commands.json', 'utf8');
      return JSON.parse(data);
    }
    return { commands: [] }; // Retourne un objet vide si le fichier n'existe pas
  } catch (error) {
    console.error('Erreur lors du chargement des commandes depuis commands.json:', error);
    return { commands: [] };
  }
};

// Sauvegarde les commandes dans un fichier JSON local
const saveCommands = (commands) => {
  try {
    fs.writeFileSync('commands.json', JSON.stringify(commands, null, 2));
  } catch (error) {
    console.error('Erreur lors de la sauvegarde des commandes dans commands.json:', error);
  }
};

// --- Endpoints API (avec vérification de l'API key) ---

// Endpoint pour récupérer les commandes en attente pour un device
app.get('/api/commands', checkApiKey, (req, res) => {
  const deviceId = req.query.deviceId;
  let commands = loadCommands(); // Charge toutes les commandes

  // Filtre par deviceId si spécifié
  if (deviceId) {
    commands.commands = commands.commands.filter(cmd => cmd.device_id === deviceId);
  }

  res.json(commands); // Retourne les commandes filtrées
});

// Endpoint pour ajouter une commande (y compris de recharge)
app.post('/api/commands', checkApiKey, async (req, res) => {
  try {
    console.log('Body reçu pour /api/commands (POST):', req.body);
    
    const { device_id, command_type, parameters, timestamp } = req.body;
    
    // Vérification des champs de base requis
    if (!device_id || !command_type) {
      console.log('Erreur: device_id ou command_type manquant');
      return res.status(400).json({ error: 'device_id et command_type sont requis' });
    }
    
    // --- Logique spécifique pour les commandes de recharge d'énergie ---
    if (command_type === 'recharge_energy') {
      if (!parameters || typeof parameters.energy_amount !== 'number' || parameters.energy_amount <= 0) {
        console.log('Erreur: energy_amount invalide ou manquant pour recharge_energy');
        return res.status(400).json({ error: 'energy_amount doit être un nombre positif pour la commande recharge_energy' });
      }

      const energyAmount = parameters.energy_amount;

      // 1. Récupérer la dernière valeur d'énergie et autres données pour cet appareil depuis la DB
      const latestDataResult = await pool.query(
        'SELECT voltage, current1, current2, energy1, energy2, relay1_status, relay2_status FROM mesures WHERE device_id = $1 ORDER BY created_at DESC LIMIT 1',
        [device_id]
      );

      let currentVoltage = 0.0;
      let currentCurrent1 = 0.0;
      let currentCurrent2 = 0.0;
      let currentEnergy1 = 0.0;
      let currentEnergy2 = 0.0;
      let currentRelay1Status = false;
      let currentRelay2Status = false;

      if (latestDataResult.rows.length > 0) {
        const latestData = latestDataResult.rows[0];
        currentVoltage = parseFloat(latestData.voltage) || 0.0;
        currentCurrent1 = parseFloat(latestData.current1) || 0.0;
        currentCurrent2 = parseFloat(latestData.current2) || 0.0;
        currentEnergy1 = parseFloat(latestData.energy1) || 0.0;
        currentEnergy2 = parseFloat(latestData.energy2) || 0.0;
        currentRelay1Status = latestData.relay1_status ?? false;
        currentRelay2Status = latestData.relay2_status ?? false;
      }

      // 2. Ajouter le montant rechargé à l'énergie appropriée
      // On suppose que 'recharge_energy' pour 'esp32_maison1' affecte energy1, et pour 'esp32_maison2' affecte energy2.
      let newEnergy1 = currentEnergy1;
      let newEnergy2 = currentEnergy2;

      if (device_id === 'esp32_maison1') {
        newEnergy1 += energyAmount;
        console.log(`Recharge pour maison1. Ancienne énergie1: ${currentEnergy1}, Nouvelle énergie1: ${newEnergy1}`);
      } else if (device_id === 'esp32_maison2') {
        newEnergy2 += energyAmount;
        console.log(`Recharge pour maison2. Ancienne énergie2: ${currentEnergy2}, Nouvelle énergie2: ${newEnergy2}`);
      } else {
        console.warn(`Commande recharge_energy pour un deviceId inconnu: ${device_id}. Énergie non mise à jour dans la DB.`);
      }

      // 3. Insérer une nouvelle entrée dans la table 'mesures' avec l'énergie mise à jour et les autres valeurs conservées
      await pool.query(
        'INSERT INTO mesures (device_id, voltage, current1, current2, energy1, energy2, relay1_status, relay2_status, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)',
        [
          device_id,
          currentVoltage,
          currentCurrent1,
          currentCurrent2,
          newEnergy1, // Nouvelle valeur d'énergie pour energy1
          newEnergy2, // Nouvelle valeur d'énergie pour energy2
          currentRelay1Status,
          currentRelay2Status,
          timestamp || new Date().toISOString() // Utilise le timestamp de la commande ou un nouveau
        ]
      );
      console.log(`Énergie de ${device_id} mise à jour dans la base de données.`);
    }

    // --- Gestion de la sauvegarde des commandes dans le fichier (à considérer de migrer vers la DB) ---
    const commands = loadCommands(); // Charge les commandes existantes
    const newCommand = { // Crée la nouvelle commande à sauvegarder
      device_id,
      command_type,
      parameters: parameters || {},
      timestamp: timestamp || new Date().toISOString(),
      status: 'pending' // Le statut 'pending' est pour le suivi par l'ESP32, pas pour la base de données de mesures
    };
    
    console.log('Nouvelle commande créée et ajoutée au fichier commands.json:', newCommand);
    
    commands.commands.push(newCommand); // Ajoute la nouvelle commande à la liste
    saveCommands(commands); // Sauvegarde la liste mise à jour dans le fichier commands.json
    
    res.status(201).json(newCommand); // Répond avec la nouvelle commande créée
  } catch (error) {
    console.error('Erreur lors de l\'ajout de la commande:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Endpoint pour confirmer l'exécution d'une commande (par l'ESP32)
// Note: Utilise le timestamp comme command_id, ce qui n'est pas idéal pour un ID unique.
app.post('/api/commands/confirm', checkApiKey, (req, res) => {
  try {
    const { device_id, command_id } = req.body; // command_id est en fait le timestamp ici
    const commands = loadCommands(); // Charge les commandes depuis le fichier
    
    // Trouve la commande par device_id et timestamp
    const command = commands.commands.find(cmd => 
      cmd.device_id === device_id && cmd.timestamp === command_id
    );
    
    if (command) {
      command.status = 'executed'; // Met à jour le statut
      saveCommands(commands); // Sauvegarde la liste mise à jour
      res.json({ message: 'Commande confirmée' });
    } else {
      res.status(404).json({ error: 'Commande non trouvée' });
    }
  } catch (error) {
    console.error('Erreur lors de la confirmation de la commande:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Endpoint pour recevoir les données de l'ESP32 (mesures de capteurs)
app.post('/api/data', checkApiKey, async (req, res) => {
  // Accepte energy OU energy1/energy2 pour la flexibilité
  const { deviceId, voltage, current1, current2, energy, energy1, energy2, relay1Status, relay2Status, timestamp } = req.body;

  // Validation des champs essentiels
  if (!deviceId || typeof voltage !== 'number' || typeof current1 !== 'number' || typeof current2 !== 'number') {
    return res.status(400).json({ error: 'Données invalides', message: 'Champs obligatoires (deviceId, voltage, current1, current2) manquants ou de type incorrect.' });
  }
  // Validation qu'au moins une forme d'énergie est présente
  if (energy === undefined && (energy1 === undefined || energy2 === undefined)) {
    return res.status(400).json({ error: 'Données invalides', message: 'energy ou energy1/energy2 requis.' });
  }

  // Si energy1/energy2 sont absents, utilise 'energy' pour les deux par défaut
  const e1 = energy1 !== undefined ? energy1 : energy;
  const e2 = energy2 !== undefined ? energy2 : energy;

  try {
    // Insère les nouvelles mesures dans la base de données
    await pool.query(
      'INSERT INTO mesures (device_id, voltage, current1, current2, energy1, energy2, relay1_status, relay2_status, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)',
      [
        deviceId,
        voltage,
        current1,
        current2,
        e1, // Valeur d'énergie 1
        e2, // Valeur d'énergie 2
        relay1Status ?? false, // Par défaut à false si non fourni
        relay2Status ?? false, // Par défaut à false si non fourni
        timestamp ?? new Date().toISOString() // Utilise le timestamp fourni ou l'heure actuelle
      ]
    );
    res.status(200).json({ message: 'Données enregistrées' });
  } catch (err) {
    console.error('Erreur lors de l\'insertion des données de l\'ESP32 en base:', err);
    res.status(500).json({ error: 'Erreur lors de l\'insertion des données en base' });
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
      return res.status(404).json({ error: 'Aucune donnée trouvée pour ce deviceId' });
    }
    res.status(200).json(result.rows[0]);
  } catch (err) {
    console.error('Erreur /api/data/:deviceId/latest:', err);
    res.status(500).json({ error: 'Erreur lors de la récupération des dernières données' });
  }
});

// Récupérer l'historique des données d'un device
app.get('/api/data/:deviceId/history', checkApiKey, async (req, res) => {
  const { deviceId } = req.params;
  try {
    const result = await pool.query(
      'SELECT * FROM mesures WHERE device_id = $1 ORDER BY created_at DESC LIMIT 10', // Limite à 10 pour l'historique
      [deviceId]
    );
    res.status(200).json(result.rows);
  } catch (err) {
    console.error('Erreur /api/data/:deviceId/history:', err);
    res.status(500).json({ error: 'Erreur lors de la récupération de l\'historique' });
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
    // Ne pas renvoyer le mot de passe dans la réponse
    const user = { ...result.rows[0] };
    delete user.password; 
    res.status(200).json(user);
  } catch (err) {
    console.error('Erreur /api/login:', err);
    res.status(500).json({ error: 'Erreur lors de l\'authentification' });
  }
});

// Récupérer tous les utilisateurs (pour l'admin par exemple)
app.get('/api/utilisateurs', checkApiKey, async (req, res) => {
  try {
    const result = await pool.query('SELECT id, username, user_type FROM utilisateurs');
    res.status(200).json(result.rows);
  } catch (err) {
    console.error('Erreur /api/utilisateurs:', err);
    res.status(500).json({ error: 'Erreur lors de la récupération des utilisateurs' });
  }
});


// Gestion des erreurs globales (middleware d'erreur)
app.use((err, req, res, next) => {
  console.error(err.stack); // Log l'erreur complète
  res.status(500).json({ error: 'Erreur serveur interne' }); // Réponse générique pour le client
});

// Démarrage du serveur
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Serveur démarré sur le port ${PORT}`);
});
