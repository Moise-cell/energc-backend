# Energc Server

Serveur backend pour le projet Energc, gérant les données des appareils ESP32.

## Configuration

1. Variables d'environnement requises :
```env
PORT=3000
API_KEY=esp32_secret_key
NEON_HOST=your_host
NEON_PORT=5432
NEON_DATABASE=your_database
NEON_USER=your_user
NEON_PASSWORD=your_password
```

2. Installation :
```bash
npm install
```

3. Développement :
```bash
npm run dev
```

4. Production :
```bash
npm start
```

## API Endpoints

- `POST /api/data` : Envoyer des données de l'ESP32
- `GET /api/data/:deviceId/latest` : Obtenir les dernières données
- `POST /api/commands` : Ajouter une commande
- `GET /api/commands` : Récupérer les commandes
- `POST /api/login` : Authentification utilisateur

## Déploiement

Le projet est configuré pour être déployé sur Render.com. 