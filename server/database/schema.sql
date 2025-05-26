-- Table des mesures
CREATE TABLE IF NOT EXISTS mesures (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(50) NOT NULL,
    energy1 DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Table des utilisateurs
CREATE TABLE IF NOT EXISTS utilisateurs (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    user_type VARCHAR(20) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Table des maisons
CREATE TABLE IF NOT EXISTS maisons (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(50) NOT NULL UNIQUE,
    nom VARCHAR(100) NOT NULL,
    adresse TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index pour les recherches rapides
CREATE INDEX IF NOT EXISTS idx_mesures_device_id ON mesures(device_id);
CREATE INDEX IF NOT EXISTS idx_mesures_created_at ON mesures(created_at);
CREATE INDEX IF NOT EXISTS idx_utilisateurs_username ON utilisateurs(username);
CREATE INDEX IF NOT EXISTS idx_maisons_device_id ON maisons(device_id); 