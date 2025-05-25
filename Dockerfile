FROM debian:bullseye-slim AS build-env

# Install necessary build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-11-jdk \
    wget \
    gnupg \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -ms /bin/bash developer
USER developer
WORKDIR /home/developer

# Install Flutter
RUN curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.3-stable.tar.xz -o flutter.tar.xz \
    && tar xf flutter.tar.xz \
    && rm flutter.tar.xz
ENV PATH="/home/developer/flutter/bin:${PATH}"

# Setup Flutter
RUN flutter doctor -v
RUN flutter channel stable
RUN flutter upgrade
RUN flutter config --enable-web

# Copy files to container and build
WORKDIR /home/developer/app
COPY --chown=developer:developer . .

# Get dependencies and build
RUN flutter pub get
RUN flutter build web --release --web-renderer html

# Stage 2 - Create the run-time image
FROM nginx:1.21.1-alpine
COPY --from=build-env /home/developer/app/build/web /usr/share/nginx/html

# Add nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"] 