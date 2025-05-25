FROM debian:bullseye-slim

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Installation de Flutter
ENV FLUTTER_HOME=/flutter
ENV PATH=$FLUTTER_HOME/bin:$PATH
RUN git clone https://github.com/flutter/flutter.git $FLUTTER_HOME
RUN flutter channel stable
RUN flutter upgrade
RUN flutter config --enable-web

# Configuration du répertoire de travail
WORKDIR /app
COPY . .

# Installation des dépendances et build
RUN flutter pub get
RUN flutter build web --release

# Installation de Node.js pour le serveur
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# Installation des dépendances du serveur
WORKDIR /app/server
RUN npm install

# Retour au répertoire principal
WORKDIR /app

# Exposition du port
EXPOSE 8080

# Commande de démarrage
CMD ["sh", "-c", "cd server && npm start & cd build/web && python3 -m http.server 8080"] 