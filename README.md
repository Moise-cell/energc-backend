# EnergC Backend

Backend pour l'application EnergC, un système de gestion d'énergie.

## Configuration

1. Créer un fichier `.env` avec les variables suivantes :
```
NEON_HOST=votre-host.neon.tech
NEON_PORT=5432
NEON_DATABASE=votre-database
NEON_USER=votre-user
NEON_PASSWORD=votre-password
API_KEY=votre-api-key
FRONTEND_URL=https://votre-app-frontend.com
```

2. Installer les dépendances :
```bash
npm install
```

3. Démarrer le serveur :
```bash
npm start
```

## Déploiement sur Render

1. Créer un nouveau Web Service sur Render
2. Connecter votre dépôt Git
3. Configurer les variables d'environnement dans l'interface Render
4. Déployer !

## API Endpoints

- `GET /test/mesures` - Liste les 10 dernières mesures
- `GET /test/utilisateurs` - Liste les utilisateurs
- `POST /api/data` - Ajoute une nouvelle mesure
- `GET /api/data/:deviceId/latest` - Récupère la dernière mesure d'un device
- `POST /api/login` - Authentification utilisateur
