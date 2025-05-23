/*
 * EnergC - ESP32 Controller
 * 
 * Ce script gère :
 * - Un afficheur LCD 20x4 (I2C)
 * - Un clavier 4x4
 * - Deux capteurs de courant ACS712
 * - Un capteur de tension
 * - Deux relais
 * - Un module GSM SIM800L
 * 
 * Il communique avec une base de données Neon.tech via HTTP
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Keypad.h>
#include <EEPROM.h>
//#include <SoftwareSerial.h>
#include <SPIFFS.h>
#include <HardwareSerial.h>
#include <ZMPT101B.h>
#include <ACS712.h>
#include <math.h>
#include <time.h>

// Configuration WiFi
const char* ssid = "MoiseMb";          // Votre réseau WiFi
const char* password = "moise1234";     // Votre mot de passe WiFi

// Configuration de l'appareil
const char* deviceId = "esp32_maison1"; // Identifiant unique pour le contrôleur
const int EEPROM_SIZE = 512;

// Configuration API
const char* API_URL = "https://energc-backend.onrender.com";  // URL Render sans port
const char* apiKey = "esp32_secret_key"; // API key pour l'authentification

// Configuration des tentatives de connexion
const int MAX_WIFI_RETRIES = 10;        // Augmentation du nombre de tentatives
const int WIFI_RETRY_DELAY = 5000;      // 5 secondes entre les tentatives
const int MAX_API_RETRIES = 3;
const int API_RETRY_DELAY = 2000;

// Liste des numéros de téléphone des utilisateurs
String userPhoneNumbers[] = {
  "+243973581507", // Propriétaire
  "+243997795866", // Maison 1
  "+243974413496"  // Maison 2
};
const int userCount = 3; // Nombre d'utilisateurs
// Configuration des broches
// LCD I2C utilise les broches SDA et SCL par défaut de l'ESP32
const int VOLTAGE_SENSOR_PIN = 36;    // Capteur de tension
const int CURRENT_SENSOR1_PIN = 35;   // Capteur de courant 1
const int CURRENT_SENSOR2_PIN = 34;   // Capteur de courant 2
const int RELAY1_PIN = 5;            // Relais 1
const int RELAY2_PIN = 4;            // Relais 2
// Initialisation du module SIM800L sur un port série matériel
#define SIM800_RX_PIN 16 // RX du module SIM800L
#define SIM800_TX_PIN 17 // TX du module SIM800L
HardwareSerial sim800(2); // Utilisation du port série matériel UART2
// Seuils d'alerte pour l'énergie
const float ALERT_THRESHOLD = 1.0; // Alerte lorsque l'énergie restante est inférieure à 1 kWh
const float SHUTDOWN_THRESHOLD = 0.1; // Coupure du relais lorsque l'énergie restante est inférieure à 0.1 kWh
// Configuration du clavier 4x4
const byte ROWS = 4;
const byte COLS = 4;
char keys[ROWS][COLS] = {
  {'1','2','3','+'},
  {'4','5','6','M'},
  {'7','8','9','D'},
  {'E','0','.','A'}
};
byte rowPins[ROWS] = {13,12,14,27};
byte colPins[COLS] = {26,25,33,32};
// Initialisation des objets
LiquidCrystal_I2C lcd(0x27, 20, 4); // Remplacez 0x27 par l'adresse détectée
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);
// Variables globales
float voltage = 0.0;
float current1 = 0.0;
float current2 = 0.0;
float energy1 = 0.0;
float energy2 = 0.0;
float energy_user = 0.0;    // Ajout de la variable manquante
float energy_userr = 0.0;   // Ajout de la variable manquante
unsigned long v = 0;        // Ajout de la variable manquante
const unsigned long energyInterval = 1000; // Intervalle de temps en millisecondes
bool relay1Status = false;
bool relay2Status = false;
unsigned long lastDataSendTime = 0;
unsigned long lastCommandCheckTime = 0;
unsigned long lastMeasurementTime = 0;
unsigned long lastAlertTime = 0;
const unsigned long alertInterval = 60000; // 1 minute
String currentMessage = "";
int menuState = 0;  // 0: affichage normal, 1: menu principal, 2: sous-menu
bool maison1AlertSent = false;
bool maison1ShutdownSent = false;
bool maison2AlertSent = false;
bool maison2ShutdownSent = false;
String inputEnergy = ""; // Stocke l'entrée de l'utilisateur
const String ownerPassword = "1234"; // Mot de passe du propriétaire
String enteredPassword = "";         // Stocke l'entrée du mot de passe
bool isPasswordVerified = false;     // Indique si le mot de passe est correct
float previousCurrent1 = 0.0; // Variable pour stocker la valeur précédente du courant 1
float previousEnergy1 = 0.0;  // Variable pour stocker la valeur précédente de l'énergie 1
bool isOnline = false;  // État de la connexion
unsigned long lastOfflineSave = 0;
const unsigned long OFFLINE_SAVE_INTERVAL = 300000; // Sauvegarde toutes les 5 minutes en mode hors ligne

// Configuration des capteurs
ZMPT101B capteur_tension(36, 50.0); 
ACS712 capteur_courant1(ACS712_30A, 34);
ACS712 capteur_courant2(ACS712_30A, 35);

// Configuration des relais
#define RELAY_USER1 4
#define RELAY_USER2 5
#define RELAY_USER 23

// Facteurs de conversion
#define FACTOR_VOLTAGE 0.0061 // Exemple : Facteur de conversion pour le capteur de tension
#define FACTOR_CURRENT 0.01   // Exemple : Facteur de conversion pour le capteur ACS712
#define TIME_INTERVAL 1       // Intervalle de temps en secondes entre les lectures

unsigned long lastEnergCUpdate = 0;
const unsigned long energCUpdateInterval = 120000; // 2 minutes au lieu de 30 secondes

// Variables pour le menu
String inputBuffer = "";
bool isPasswordMode = false;
int currentMenu = 0; // 0: aucun menu, 1: menu énergie, 2: menu relais, 3: menu config

void savePhoneNumbers() {
  for (int i = 0; i < userCount; i++) {
    EEPROM.writeString(i * 20, userPhoneNumbers[i]); // 20 octets par numéro
  }
  EEPROM.commit();
}

void saveEnergyValues() {
  // Sauvegarder les valeurs d'énergie dans l'EEPROM
  EEPROM.writeFloat(0, energy1); // Sauvegarde de energy1 à l'adresse 0
  EEPROM.writeFloat(4, energy2); // Sauvegarde de energy2 à l'adresse 4
  EEPROM.commit(); // Valider les écritures dans l'EEPROM
}

void saveEnergyValuesToSPIFFS() {
    File file = SPIFFS.open("/energy.txt", FILE_WRITE);
    if (!file) {
        Serial.println("Erreur : Impossible d'ouvrir le fichier pour écrire.");
        return;
    }
    file.printf("Energy1: %.2f\nEnergy2: %.2f\n", energy1, energy2);
    file.close();
}

void savePhoneNumbersToSPIFFS() {
    File file = SPIFFS.open("/phone_numbers.txt", FILE_WRITE);
    if (!file) {
        Serial.println("Erreur : Impossible d'ouvrir le fichier pour écrire.");
        return;
    }

    for (int i = 0; i < userCount; i++) {
        file.println(userPhoneNumbers[i]); // Écrire chaque numéro sur une nouvelle ligne
    }

    file.close();
    Serial.println("Numéros de téléphone sauvegardés dans SPIFFS.");
}

void loadEnergyValuesFromSPIFFS() {
    File file = SPIFFS.open("/energy.txt", FILE_READ);
    if (!file) {
        Serial.println("Erreur : Impossible d'ouvrir le fichier pour lire.");
        return;
    }

    // Lire les données ligne par ligne
    String line;
    while (file.available()) {
        line = file.readStringUntil('\n');
        Serial.println(line);

        // Extraire les valeurs d'énergie
        if (line.startsWith("Energy1:")) {
            energy1 = line.substring(8).toFloat();
        } else if (line.startsWith("Energy2:")) {
            energy2 = line.substring(8).toFloat();
        }
    }
    file.close();
    Serial.println("Données d'énergie chargées depuis SPIFFS.");
}

void loadPhoneNumbersFromSPIFFS() {
    File file = SPIFFS.open("/phone_numbers.txt", FILE_READ);
    if (!file) {
        Serial.println("Erreur : Impossible d'ouvrir le fichier pour lire.");
        return;
    }

    int i = 0;
    while (file.available() && i < userCount) {
        userPhoneNumbers[i] = file.readStringUntil('\n'); // Lire chaque ligne
        userPhoneNumbers[i].trim(); // Supprimer les espaces ou sauts de ligne inutiles
        i++;
    }

    file.close();
    Serial.println("Numéros de téléphone chargés depuis SPIFFS.");
}

void loadPhoneNumbers() {
  for (int i = 0; i < userCount; i++) {
    userPhoneNumbers[i] = EEPROM.readString(i * 20); // Charger les numéros depuis l'EEPROM
  }
}

void modifyPhoneNumber(int index, String newNumber) {
    if (index >= 0 && index < userCount) {
        userPhoneNumbers[index] = newNumber;
        savePhoneNumbersToSPIFFS(); // Sauvegarder les modifications dans SPIFFS
        Serial.println("Numéro de téléphone modifié et sauvegardé.");
    } else {
        Serial.println("Index invalide.");
    }
}

void sendAlertSMS(String message, String phoneNumber) {
    sim800.println("AT+CMGF=1"); // Mode texte
    delay(100);
    sim800.println("AT+CMGS=\"" + phoneNumber + "\"");
    delay(100);
    sim800.print(message);
    delay(100);
    sim800.write(26); // CTRL+Z pour envoyer le message
    delay(1000);
    Serial.println("SMS envoyé à " + phoneNumber);
}

void readSensors() {
    voltage = capteur_tension.getRmsVoltage();
    current1 = capteur_courant1.getCurrentAC();
    current2 = capteur_courant2.getCurrentAC();
    energy1 += current1 * voltage * TIME_INTERVAL;
    energy2 += current2 * voltage * TIME_INTERVAL;
}

void manageRelays() {
    // Relais 1
    if (energy1 < SHUTDOWN_THRESHOLD) {
        digitalWrite(RELAY_USER1, HIGH);
        relay1Status = false;
    } else {
        digitalWrite(RELAY_USER1, LOW);
        relay1Status = true;
    }
    // Relais 2
    if (energy2 < SHUTDOWN_THRESHOLD) {
        digitalWrite(RELAY_USER2, HIGH);
        relay2Status = false;
    } else {
        digitalWrite(RELAY_USER2, LOW);
        relay2Status = true;
    }
}

void scanWiFiNetworks() {
  Serial.println("\nScan des réseaux WiFi disponibles...");
  int n = WiFi.scanNetworks();
  
  if (n == 0) {
    Serial.println("Aucun réseau trouvé!");
  } else {
    Serial.print(n);
    Serial.println(" réseaux trouvés:");
    
    for (int i = 0; i < n; ++i) {
      Serial.print(i + 1);
      Serial.print(": ");
      Serial.print(WiFi.SSID(i));
      Serial.print(" (");
      Serial.print(WiFi.RSSI(i));
      Serial.print(" dBm)");
      Serial.print(" - ");
      Serial.println(WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "Non sécurisé" : "Sécurisé");
      delay(10);
    }
  }
  Serial.println();
}

void connectToWiFi() {
  Serial.println("\n=== Configuration WiFi ===");
  Serial.print("SSID: ");
  Serial.println(ssid);
  Serial.print("Password: ");
  Serial.println(password);
  
  // Scanner les réseaux disponibles
  scanWiFiNetworks();
  
  // Configuration du mode WiFi
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(1000);
  
  Serial.println("\nTentative de connexion...");
  lcd.clear();
  lcd.print("Connexion WiFi...");
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < MAX_WIFI_RETRIES) {
    Serial.print("Tentative ");
    Serial.print(attempts + 1);
    Serial.print("/");
    Serial.println(MAX_WIFI_RETRIES);
    
    WiFi.begin(ssid, password);
    
    // Attendre la connexion avec un timeout
    int timeout = 0;
    while (WiFi.status() != WL_CONNECTED && timeout < 20) {
      delay(500);
      Serial.print(".");
      timeout++;
    }
    Serial.println();
    
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nWiFi connecté avec succès!");
      Serial.print("Adresse IP: ");
      Serial.println(WiFi.localIP());
      Serial.print("Masque de sous-réseau: ");
      Serial.println(WiFi.subnetMask());
      Serial.print("Passerelle: ");
      Serial.println(WiFi.gatewayIP());
      Serial.print("DNS: ");
      Serial.println(WiFi.dnsIP());
      Serial.print("Force du signal (RSSI): ");
      Serial.println(WiFi.RSSI());
      
      lcd.clear();
      lcd.print("WiFi connecte");
      lcd.setCursor(0, 1);
      lcd.print(WiFi.localIP());
      return;
    }
    
    attempts++;
    if (attempts < MAX_WIFI_RETRIES) {
      Serial.println("Échec de la connexion, nouvelle tentative...");
      lcd.clear();
      lcd.print("Tentative ");
      lcd.print(attempts + 1);
      lcd.print("/");
      lcd.print(MAX_WIFI_RETRIES);
      delay(WIFI_RETRY_DELAY);
    }
  }
  
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("\nÉchec de la connexion WiFi après plusieurs tentatives");
    Serial.println("Vérifiez que:");
    Serial.println("1. Le SSID est correct: " + String(ssid));
    Serial.println("2. Le mot de passe est correct");
    Serial.println("3. Le routeur est à portée");
    Serial.println("4. Le routeur n'a pas de restrictions (filtrage MAC, etc.)");
    
    lcd.clear();
    lcd.print("Erreur WiFi");
    lcd.setCursor(0, 1);
    lcd.print("Verifiez config");
  }
}

void sendDataToServer() {
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n=== Envoi des données au serveur ===");
    Serial.println("État WiFi : Connecté");
    Serial.print("Adresse IP : ");
    Serial.println(WiFi.localIP());
    Serial.print("Force du signal (RSSI) : ");
    Serial.println(WiFi.RSSI());
    
    int retryCount = 0;
    bool success = false;
    
    while (!success && retryCount < MAX_API_RETRIES) {
      HTTPClient http;
      Serial.println("\nTentative de connexion à l'API...");
      Serial.print("URL : ");
      Serial.println(API_URL);
      
      http.begin(API_URL);
      http.addHeader("Content-Type", "application/json");
      http.addHeader("x-api-key", apiKey);
      http.addHeader("Accept", "application/json");
      
      // Envoyer les données dans le format attendu par le backend
      StaticJsonDocument<1024> doc;
      doc["deviceId"] = deviceId;
      doc["voltage"] = voltage;
      doc["current1"] = current1;
      doc["current2"] = current2;
      doc["energy1"] = energy_user;
      doc["energy2"] = energy_userr;
      doc["relay1Status"] = relay1Status;
      doc["relay2Status"] = relay2Status;
      doc["timestamp"] = getTimestamp();
      
      String jsonData;
      serializeJson(doc, jsonData);
      
      Serial.println("\nDétails de la requête :");
      Serial.println("Headers :");
      Serial.println("  Content-Type: application/json");
      Serial.println("  x-api-key: " + String(apiKey));
      Serial.println("  Accept: application/json");
      Serial.println("Données envoyées :");
      Serial.println(jsonData);
      
      Serial.println("\nEnvoi de la requête...");
      int httpResponseCode = http.POST(jsonData);
      
      if (httpResponseCode > 0) {
        String response = http.getString();
        Serial.println("\nRéponse du serveur :");
        Serial.println("Code : " + String(httpResponseCode));
        Serial.println("Contenu : " + response);
        
        if (httpResponseCode == 200 || httpResponseCode == 201) {
          success = true;
          Serial.println("Données envoyées avec succès !");
          lcd.clear();
          lcd.print("Donnees envoyees");
          lcd.setCursor(0, 1);
          lcd.print("OK");
          delay(1000);
        } else {
          Serial.println("Erreur serveur : " + String(httpResponseCode));
          Serial.println("Réponse : " + response);
          Serial.println("Détails de l'erreur :");
          if (httpResponseCode == 401) {
            Serial.println("Erreur d'authentification - Vérifiez la clé API");
          } else if (httpResponseCode == 404) {
            Serial.println("URL non trouvée - Vérifiez l'URL de l'API");
          } else if (httpResponseCode == 500) {
            Serial.println("Erreur serveur interne");
          }
        }
      } else {
        Serial.println("\nErreur de connexion :");
        Serial.println("Code : " + String(httpResponseCode));
        Serial.println("Erreur : " + http.errorToString(httpResponseCode));
        Serial.println("Vérifiez que :");
        Serial.println("1. L'URL de l'API est correcte");
        Serial.println("2. Le serveur est en ligne");
        Serial.println("3. Le port 30000 est ouvert");
      }
      
      http.end();
      
      if (!success) {
        retryCount++;
        if (retryCount < MAX_API_RETRIES) {
          Serial.print("\nNouvelle tentative dans ");
          Serial.print(API_RETRY_DELAY / 1000);
          Serial.println(" secondes...");
          lcd.clear();
          lcd.print("Nouvelle tentative");
          lcd.setCursor(0, 1);
          lcd.print(retryCount);
          lcd.print("/");
          lcd.print(MAX_API_RETRIES);
          delay(API_RETRY_DELAY);
        }
      }
    }
    
    if (!success) {
      Serial.println("\nÉchec de l'envoi des données après plusieurs tentatives");
      Serial.println("Vérifiez que :");
      Serial.println("1. L'URL de l'API est correcte : " + String(API_URL));
      Serial.println("2. La clé API est valide : " + String(apiKey));
      Serial.println("3. Le serveur est en ligne et accessible");
      Serial.println("4. Le port 30000 est ouvert sur le serveur");
      lcd.clear();
      lcd.print("Erreur envoi");
      lcd.setCursor(0, 1);
      lcd.print("Donnees sauvegardees");
      saveEnergyValuesToSPIFFS();
    }
  } else {
    Serial.println("\nPas de connexion WiFi");
    Serial.println("Tentative de reconnexion...");
    lcd.clear();
    lcd.print("Pas de WiFi");
    connectToWiFi();
  }
}

void checkServerCommands() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String commandUrl = String(API_URL) + "/api/commands";
    http.begin(commandUrl);
    http.addHeader("x-api-key", apiKey);
    
    int httpResponseCode = http.GET();
    
    if (httpResponseCode == 200) {
      String payload = http.getString();
      Serial.println("Commandes reçues: " + payload);
      
      StaticJsonDocument<512> doc;
      DeserializationError error = deserializeJson(doc, payload);
      
      if (!error) {
        JsonArray commands = doc["commands"].as<JsonArray>();
        for (JsonObject command : commands) {
          String commandType = command["command_type"] | "";
          JsonObject parameters = command["parameters"] | JsonObject();
          processCommand(commandType.c_str(), parameters);
        }
      }
    }
    http.end();
  }
}

void processCommand(const char* commandType, const JsonObject& parameters) {
  if (strcmp(commandType, "recharge_energy") == 0) {
    float energyAmount = parameters["energy_amount"] | 0.0;
    Serial.print("Montant de la recharge: ");
    Serial.println(energyAmount);
    
    if (strcmp(deviceId, "esp32_maison1") == 0) {
      energy_user += energyAmount;
      energy1 = energy_user;
      Serial.print("Nouvelle énergie maison 1: ");
      Serial.println(energy_user);
      saveEnergyValuesToSPIFFS();
    } else if (strcmp(deviceId, "esp32_maison2") == 0) {
      energy_userr += energyAmount;
      energy2 = energy_userr;
      Serial.print("Nouvelle énergie maison 2: ");
      Serial.println(energy_userr);
      saveEnergyValuesToSPIFFS();
    }
  }
}

void updateLCD() {
    if (menuState == 0) {
        lcd.clear();
        
        // Ligne 1: État de la connexion
        lcd.setCursor(0, 0);
        lcd.print(isOnline ? "En ligne" : "Hors ligne");
        
        // Ligne 2: Maison 1
        lcd.setCursor(0, 1);
        lcd.print("M1: ");
        lcd.print(current1, 1);
        lcd.print("A ");
        lcd.print(energy_user, 1);
        lcd.print("kWh");
        
        // Ligne 3: Maison 2
        lcd.setCursor(0, 2);
        lcd.print("M2: ");
        lcd.print(current2, 1);
        lcd.print("A ");
        lcd.print(energy_userr, 1);
        lcd.print("kWh");
        
        // Ligne 4: État des relais
        lcd.setCursor(0, 3);
        lcd.print("R1:");
        lcd.print(relay1Status ? "ON " : "OFF");
        lcd.print(" R2:");
        lcd.print(relay2Status ? "ON" : "OFF");
    }
}

void handleKeypadInput() {
    char key = keypad.getKey();
    if (key) {
        Serial.print("Touche pressée : ");
        Serial.println(key);
        
        switch(menuState) {
            case 0: // Mode affichage normal
                if (key == 'M') { // M pour Menu
                    menuState = 1;
                    showMainMenu();
                }
                break;
                
            case 1: // Menu principal
                handleMainMenu(key);
                break;
                
            case 2: // Sous-menu
                handleSubMenu(key);
                break;
        }
    }
}

void showMainMenu() {
    lcd.clear();
    lcd.print("1: Energie");
    lcd.setCursor(0, 1);
    lcd.print("2: Relais");
    lcd.setCursor(0, 2);
    lcd.print("3: Config");
    lcd.setCursor(0, 3);
    lcd.print("E: Retour");
}

void handleMainMenu(char key) {
    switch(key) {
        case '1':
            menuState = 2;
            currentMenu = 1;
            showEnergyMenu();
            break;
        case '2':
            menuState = 2;
            currentMenu = 2;
            showRelayMenu();
            break;
        case '3':
            menuState = 2;
            currentMenu = 3;
            showConfigMenu();
            break;
        case 'E':
            menuState = 0;
            currentMenu = 0;
            updateLCD();
            break;
    }
}

void showEnergyMenu() {
    lcd.clear();
    lcd.print("Energie");
    lcd.setCursor(0, 1);
    lcd.print("1: M1: ");
    lcd.print(energy_user);
    lcd.setCursor(0, 2);
    lcd.print("2: M2: ");
    lcd.print(energy_userr);
    lcd.setCursor(0, 3);
    lcd.print("E: Retour");
}

void showRelayMenu() {
    lcd.clear();
    lcd.print("Controle Relais");
    lcd.setCursor(0, 1);
    lcd.print("1: R1: ");
    lcd.print(relay1Status ? "ON" : "OFF");
    lcd.setCursor(0, 2);
    lcd.print("2: R2: ");
    lcd.print(relay2Status ? "ON" : "OFF");
    lcd.setCursor(0, 3);
    lcd.print("E: Retour");
}

void showConfigMenu() {
    lcd.clear();
    lcd.print("Configuration");
    lcd.setCursor(0, 1);
    lcd.print("1: WiFi");
    lcd.setCursor(0, 2);
    lcd.print("2: Reset");
    lcd.setCursor(0, 3);
    lcd.print("E: Retour");
}

void handleSubMenu(char key) {
    switch(key) {
        case '1':
            if (menuState == 2) {
                if (isEnergyMenu()) {
                    energy_user += 1.0;
                    saveEnergyValuesToSPIFFS();
                    lcd.clear();
                    lcd.print("Recharge +1.0 kWh");
                    lcd.setCursor(0, 1);
                    lcd.print("Total: ");
                    lcd.print(energy_user);
                    lcd.print(" kWh");
                    delay(2000);
                } else if (isRelayMenu()) {
                    relay1Status = !relay1Status;
                    digitalWrite(RELAY_USER1, relay1Status ? LOW : HIGH);
                } else if (isConfigMenu()) {
                    connectToWiFi();
                }
            }
            break;
        case '2':
            if (menuState == 2) {
                if (isEnergyMenu()) {
                    energy_userr += 1.0;
                    saveEnergyValuesToSPIFFS();
                    lcd.clear();
                    lcd.print("Recharge +1.0 kWh");
                    lcd.setCursor(0, 1);
                    lcd.print("Total: ");
                    lcd.print(energy_userr);
                    lcd.print(" kWh");
                    delay(2000);
                } else if (isRelayMenu()) {
                    relay2Status = !relay2Status;
                    digitalWrite(RELAY_USER2, relay2Status ? LOW : HIGH);
                } else if (isConfigMenu()) {
                    ESP.restart();
                }
            }
            break;
        case 'E':
            menuState = 1;
            currentMenu = 0;
            showMainMenu();
            break;
    }
}

bool isEnergyMenu() {
    return currentMenu == 1;
}

bool isRelayMenu() {
    return currentMenu == 2;
}

bool isConfigMenu() {
    return currentMenu == 3;
}

void checkWiFiConnection() {
  if (WiFi.status() != WL_CONNECTED) {
    if (isOnline) {
      Serial.println("Connexion WiFi perdue");
      isOnline = false;
      lcd.clear();
      lcd.print("Connexion perdue");
      lcd.setCursor(0, 1);
      lcd.print("Mode hors ligne");
      delay(2000);
    }
    // Tenter de se reconnecter toutes les 30 secondes
    static unsigned long lastReconnectAttempt = 0;
    if (millis() - lastReconnectAttempt > 30000) {
      lastReconnectAttempt = millis();
      connectToWiFi();
    }
  } else if (!isOnline) {
    Serial.println("Connexion WiFi rétablie");
    isOnline = true;
    lcd.clear();
    lcd.print("Connexion retablie");
    delay(2000);
  }
}

void saveOfflineData() {
  if (!isOnline && millis() - lastOfflineSave > OFFLINE_SAVE_INTERVAL) {
    Serial.println("Sauvegarde des données hors ligne...");
    saveEnergyValuesToSPIFFS();
    lastOfflineSave = millis();
  }
}

void setup() {
  Wire.begin();
  Serial.begin(115200);
  delay(1000); // Attendre que le port série soit prêt
  
  Serial.println("\n=== Démarrage du système ===");
  
  // Initialisation de l'écran LCD
  lcd.begin();
  lcd.backlight();
  lcd.clear();
  lcd.print("Demarrage...");
  delay(1000);
  
  // Connexion WiFi
  connectToWiFi();
  
  if (!SPIFFS.begin(true)) {
        Serial.println("Erreur : SPIFFS non initialisé.");
        return;
    }

    Serial.println("SPIFFS initialisé avec succès.");

    // Charger les numéros de téléphone depuis SPIFFS
    loadPhoneNumbersFromSPIFFS();

    // Charger les données d'énergie depuis SPIFFS
    loadEnergyValuesFromSPIFFS();

    // Autres initialisations...
    pinMode(RELAY_USER1, OUTPUT);
    pinMode(RELAY_USER2, OUTPUT);
    pinMode(RELAY_USER, OUTPUT);
    digitalWrite(RELAY_USER1, HIGH);
    digitalWrite(RELAY_USER2, HIGH);
    digitalWrite(RELAY_USER, LOW);

    // Initialisation des capteurs
    capteur_tension.setSensitivity(500.0f);
    capteur_courant1.calibrate();
    capteur_courant2.calibrate();

    Serial.println("Test du clavier 4x4");
}

void loop() {
  checkWiFiConnection();
  checkAlerts();
  
  if(v < 10000000) {
    v = v + 1;
  }
  if(v > 1000000) {
    v = 0;
  }
  
  // Lecture des capteurs
  voltage = capteur_tension.getRmsVoltage();
  current1 = capteur_courant1.getCurrentAC();
  current2 = capteur_courant2.getCurrentAC();
  
  // Calcul de l'énergie
  energy1 = voltage * current1 * (energyInterval / 3600000.0);
  energy2 = voltage * current2 * (energyInterval / 3600000.0);
  
  // Mise à jour de l'énergie des utilisateurs
  if((v % 2) == 0 && v > 0) {
    if(energy_user > 0) {
      energy_user = energy_user - energy1;
    }
    if(energy_userr > 0) {
      energy_userr = energy_userr - energy2;
    }
  }
  
  // Contrôle des relais
  if(energy_user <= 0) {
    energy_user = 0;
    digitalWrite(RELAY_USER1, HIGH);
  } else {
    digitalWrite(RELAY_USER1, LOW);
  }
  
  if(energy_userr <= 0) {
    energy_userr = 0;
    digitalWrite(RELAY_USER2, HIGH);
  } else {
    digitalWrite(RELAY_USER2, LOW);
  }
  
  // Envoi des données
  if(isOnline) {
    if(millis() - lastEnergCUpdate >= energCUpdateInterval) {
      Serial.println("\n=== Intervalle d'envoi atteint ===");
      sendDataToServer();
      lastEnergCUpdate = millis();
    }
    
    // Vérifier les commandes toutes les minutes
    if (millis() - lastCommandCheckTime >= 60000) {
      checkServerCommands();
      lastCommandCheckTime = millis();
    }
  } else {
    saveOfflineData();
  }
  
  handleKeypadInput();
  updateLCD();
  delay(1000);
}

String getTimestamp() {
    // Format: "2024-03-14T12:00:00Z"
    time_t now;
    struct tm timeinfo;
    if (!getLocalTime(&timeinfo)) {
        Serial.println("Échec de l'obtention du temps");
        return "2024-03-14T12:00:00Z";
    }
    time(&now);
    char timeStringBuff[50];
    strftime(timeStringBuff, sizeof(timeStringBuff), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
    return String(timeStringBuff);
}

void checkAlerts() {
  // Vérifier les seuils d'alerte pour la maison 1
  if (energy_user <= ALERT_THRESHOLD && !maison1AlertSent) {
    sendAlertSMS("Alerte : Énergie faible pour Maison 1", userPhoneNumbers[1]);
    maison1AlertSent = true;
  } else if (energy_user > ALERT_THRESHOLD) {
    maison1AlertSent = false;
  }

  // Vérifier les seuils d'alerte pour la maison 2
  if (energy_userr <= ALERT_THRESHOLD && !maison2AlertSent) {
    sendAlertSMS("Alerte : Énergie faible pour Maison 2", userPhoneNumbers[2]);
    maison2AlertSent = true;
  } else if (energy_userr > ALERT_THRESHOLD) {
    maison2AlertSent = false;
  }

  // Vérifier les seuils de coupure
  if (energy_user <= SHUTDOWN_THRESHOLD && !maison1ShutdownSent) {
    sendAlertSMS("Coupure : Énergie épuisée pour Maison 1", userPhoneNumbers[0]);
    maison1ShutdownSent = true;
  } else if (energy_user > SHUTDOWN_THRESHOLD) {
    maison1ShutdownSent = false;
  }

  if (energy_userr <= SHUTDOWN_THRESHOLD && !maison2ShutdownSent) {
    sendAlertSMS("Coupure : Énergie épuisée pour Maison 2", userPhoneNumbers[0]);
    maison2ShutdownSent = true;
  } else if (energy_userr > SHUTDOWN_THRESHOLD) {
    maison2ShutdownSent = false;
  }
}

void checkServerConnection() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(API_URL);
    int httpCode = http.GET();
    if (httpCode == HTTP_CODE_OK) {
      Serial.println("4. Le port 30000 est ouvert sur le serveur");
    }
    http.end();
  }
}
