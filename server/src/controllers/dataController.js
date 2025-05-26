const pool = require('../config/database');
const logger = require('../config/logger');

const dataController = {
  // Obtenir les dernières données d'un appareil
  async getLatestData(req, res) {
    const apiKey = req.headers['x-api-key'];
    if (apiKey !== process.env.API_KEY) {
      logger.warn('Tentative d\'accès non autorisée');
      return res.status(401).json({ error: 'Unauthorized' });
    }

    try {
      const { deviceId } = req.params;
      const result = await pool.query(
        'SELECT * FROM device_data WHERE device_id = $1 ORDER BY timestamp DESC LIMIT 1',
        [deviceId]
      );

      if (result.rows.length === 0) {
        logger.info(`Aucune donnée trouvée pour ${deviceId}`);
        return res.status(404).json({ error: 'No data found' });
      }

      logger.info(`Données récupérées pour ${deviceId}`, { data: result.rows[0] });
      res.json(result.rows[0]);
    } catch (err) {
      logger.error('Erreur lors de la récupération des données', { error: err.message });
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  // Enregistrer de nouvelles données
  async saveData(req, res) {
    const apiKey = req.headers['x-api-key'];
    if (apiKey !== process.env.API_KEY) {
      logger.warn('Tentative d\'accès non autorisée');
      return res.status(401).json({ error: 'Unauthorized' });
    }

    try {
      const {
        device_id,
        voltage,
        current1,
        current2,
        energy1,
        energy2,
        relay1_status,
        relay2_status
      } = req.body;

      const result = await pool.query(
        `INSERT INTO device_data (
          device_id, voltage, current1, current2,
          energy1, energy2, relay1_status, relay2_status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *`,
        [device_id, voltage, current1, current2, energy1, energy2, relay1_status, relay2_status]
      );

      logger.info('Nouvelles données enregistrées', { data: result.rows[0] });
      res.status(201).json(result.rows[0]);
    } catch (err) {
      logger.error('Erreur lors de l\'enregistrement des données', { error: err.message });
      res.status(500).json({ error: 'Internal server error' });
    }
  }
};

module.exports = dataController; 