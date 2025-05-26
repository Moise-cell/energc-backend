const express = require('express');
const router = express.Router();
const dataController = require('../controllers/dataController');

// Route de santé
router.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Routes pour les données
router.get('/data/:deviceId/latest', dataController.getLatestData);
router.post('/data', dataController.saveData);

module.exports = router; 