/*
 * EnergC - Contrôleur ESP32
 *
 * Ce script gère :
 * - Un afficheur LCD 20x4 (I2C)
 * - Un clavier 4x4
 * - Deux capteurs de courant ACS712
 * - Un capteur de tension ZMPT101B
 * - Deux relais
 * - Un module GSM SIM800L
 *
 * Il communique avec une base de données Neon.tech via une API sur Render.com
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Keypad.h>
#include <SPIFFS.h>
#include <HardwareSerial.h>
#include <ZMPT101B.h>
#include <ACS712.h>
#include <math.h>
#include <time.h>

const char* ssid = "MoiseMb";
const char* password = "moise1234";
const char* deviceId = "esp32_maison1";
const char* BASE_API_URL = "https://energc-server.onrender.com/api";
const char* DATA_SEND_PATH = "/data";
const char* COMMANDS_FETCH_PATH = "/commands";
const char* apiKey = "esp32_secret_key";

const int MAX_WIFI_RETRIES = 10;
const int WIFI_RETRY_DELAY = 5000;
const int MAX_API_RETRIES = 3;
const int API_RETRY_DELAY = 2000;

String userPhoneNumbers[] = {
  "+243973581507",
  "+243997795866",
  "+243974413496"
};
const int userCount = 3;

const int VOLTAGE_SENSOR_PIN = 36;
const int CURRENT_SENSOR1_PIN = 35;
const int CURRENT_SENSOR2_PIN = 34;
const int RELAY1_PIN = 5;
const int RELAY2_PIN = 4;

#define SIM800_RX_PIN 16
#define SIM800_TX_PIN 17
HardwareSerial sim800(2);

const float ALERT_THRESHOLD = 1.0;
const float SHUTDOWN_THRESHOLD = 0.1;

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
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);

LiquidCrystal_I2C lcd(0x27, 20, 4);
ZMPT101B capteur_tension(VOLTAGE_SENSOR_PIN, 50.0);
ACS712 capteur_courant1(ACS712_30A, CURRENT_SENSOR1_PIN);
ACS712 capteur_courant2(ACS712_30A, CURRENT_SENSOR2_PIN);

float voltage = 0.0;
float current1 = 0.0;
float current2 = 0.0;
float energy1_instant = 0.0;
float energy2_instant = 0.0;
float energy_user = 10.0;
float energy_userr = 15.0;
const unsigned long energyInterval = 1000;

bool relay1Status = true;
bool relay2Status = true;

unsigned long lastDataSendTime = 0;
unsigned long lastCommandCheckTime = 0;
unsigned long lastMeasurementTime = 0;
unsigned long lastAlertTime = 0;
const unsigned long alertInterval = 60000;

int menuState = 0;
String inputBuffer = "";
const String ownerPassword = "1234";
String enteredPassword = "";
bool isPasswordMode = false;
int previousMenuBeforePassword = 0;

bool maison1AlertSent = false;
bool maison1ShutdownSent = false;
bool maison2AlertSent = false;
bool maison2ShutdownSent = false;

bool isOnline = false;
unsigned long lastOfflineSave = 0;
const unsigned long OFFLINE_SAVE_INTERVAL = 300000;
unsigned long lastEnergCUpdate = 0;
const unsigned long energCUpdateInterval = 20000;

unsigned long lastWiFiRetry = 0;
const unsigned long WIFI_RETRY_INTERVAL = 600000; // 10 minutes en ms

void saveEnergyValuesToSPIFFS();
void savePhoneNumbersToSPIFFS();
void loadEnergyValuesFromSPIFFS();
void loadPhoneNumbersFromSPIFFS();
void modifyPhoneNumber(int index, String newNumber);
void sendAlertSMS(String message, String phoneNumber);
void readSensors();
void manageRelays();
void scanWiFiNetworks();
void connectToWiFi();
void sendDataToServer();
void checkServerCommands();
void processCommand(const char* commandType, const JsonObject& parameters);
String getTimestamp();
void updateLCD();
void handleKeypadInput();
void showMainMenu();
void handleMainMenu(char key);
void showRelayMenu();
void handleRelayMenu(char key);
void showConfigPhoneMenu();
void handleConfigPhoneMenu(char key);
void enterPasswordMode();
void handlePasswordInput(char key);
void clearPassword();
void verifyPassword();
void checkWiFiConnection();
void saveOfflineData();
void checkAlerts();

void setup() {
  Serial.begin(115200);
  lcd.begin();
  lcd.backlight();
  lcd.clear();
  lcd.print("Demarrage EnergC...");
  Serial.println("Demarrage ESP32.");

  if (!SPIFFS.begin(true)) {
    Serial.println("Erreur: Impossible de monter le système de fichiers SPIFFS.");
    lcd.setCursor(0,1);
    lcd.print("SPIFFS Erreur!");
    delay(3000);
    ESP.restart();
  }
  Serial.println("SPIFFS monté avec succès.");

  loadEnergyValuesFromSPIFFS();
  loadPhoneNumbersFromSPIFFS();

  sim800.begin(9600, SERIAL_8N1, SIM800_RX_PIN, SIM800_TX_PIN);
  delay(100);
  Serial.println("SIM800L initialisé sur UART2.");
  sim800.println("AT");
  delay(1000);
  while(sim800.available()) {
    Serial.write(sim800.read());
  }

  pinMode(RELAY1_PIN, OUTPUT);
  pinMode(RELAY2_PIN, OUTPUT);
  digitalWrite(RELAY1_PIN, relay1Status ? LOW : HIGH);
  digitalWrite(RELAY2_PIN, relay2Status ? LOW : HIGH);

  Serial.println("Calibration des capteurs ACS712. Assurez-vous qu'aucune charge n'est connectée.");
  lcd.setCursor(0, 2);
  lcd.print("Calib. Courant...");
  capteur_courant1.calibrate();
  capteur_courant2.calibrate();
  Serial.println("Capteurs ACS712 calibrés.");
  lcd.setCursor(0, 2);
  lcd.print("Capteurs OK!     ");

  connectToWiFi();

  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.println("\nAttente de la synchronisation NTP...");
  lcd.setCursor(0, 2);
  lcd.print("Sync NTP...");
  time_t now = time(nullptr);
  while (now < 8 * 3600 * 2) {
    delay(500);
    now = time(nullptr);
  }
  Serial.println("Heure synchronisée.");
  lcd.setCursor(0, 2);
  lcd.print("NTP OK!          ");

  lastDataSendTime = millis();
  lastCommandCheckTime = millis();
  lastMeasurementTime = millis();
  lastAlertTime = millis();
}

void loop() {
  handleKeypadInput();
  if (millis() - lastMeasurementTime >= energyInterval) {
    readSensors();
    manageRelays();
    updateLCD();
    lastMeasurementTime = millis();
  }
  if (millis() - lastEnergCUpdate >= energCUpdateInterval) {
    sendDataToServer();
    checkServerCommands();
    lastEnergCUpdate = millis();
  }
  if (millis() - lastAlertTime >= alertInterval) {
    checkAlerts();
    lastAlertTime = millis();
  }
  if (!isOnline && (millis() - lastOfflineSave >= OFFLINE_SAVE_INTERVAL)) {
    saveOfflineData();
    lastOfflineSave = millis();
  }

  if (!isOnline && (millis() - lastWiFiRetry > WIFI_RETRY_INTERVAL)) {
    connectToWiFi();
    lastWiFiRetry = millis();
  }
  checkWiFiConnection();
}

void saveEnergyValuesToSPIFFS() {
    File file = SPIFFS.open("/energy.txt", FILE_WRITE);
    if (!file) {
        Serial.println("Erreur : Impossible d'ouvrir le fichier pour écrire les énergies.");
        return;
    }
    file.printf("Energy1: %.2f\nEnergy2: %.2f\nRelay1: %d\nRelay2: %d\n", energy_user, energy_userr, relay1Status, relay2Status);
    file.close();
    Serial.println("Données d'énergie et états des relais sauvegardés dans SPIFFS.");
}

void savePhoneNumbersToSPIFFS() {
    File file = SPIFFS.open("/phone_numbers.txt", FILE_WRITE);
    if (!file) {
        Serial.println("Erreur : Impossible d'ouvrir le fichier pour écrire les numéros de téléphone.");
        return;
    }
    for (int i = 0; i < userCount; i++) {
        file.println(userPhoneNumbers[i]);
    }
    file.close();
    Serial.println("Numéros de téléphone sauvegardés dans SPIFFS.");
}

void loadEnergyValuesFromSPIFFS() {
    File file = SPIFFS.open("/energy.txt", FILE_READ);
    if (!file) {
        Serial.println("Fichier energy.txt non trouvé, initialisation des énergies/relais aux valeurs par défaut.");
        return;
    }
    String line;
    while (file.available()) {
        line = file.readStringUntil('\n');
        line.trim();
        if (line.startsWith("Energy1:")) {
            energy_user = line.substring(line.indexOf(":") + 1).toFloat();
        } else if (line.startsWith("Energy2:")) {
            energy_userr = line.substring(line.indexOf(":") + 1).toFloat();
        } else if (line.startsWith("Relay1:")) {
            relay1Status = (line.substring(line.indexOf(":") + 1).toInt() == 1);
        } else if (line.startsWith("Relay2:")) {
            relay2Status = (line.substring(line.indexOf(":") + 1).toInt() == 1);
        }
    }
    file.close();
    Serial.println("Données d'énergie et états des relais chargés depuis SPIFFS.");
    Serial.print("M1: "); Serial.print(energy_user); Serial.print(" kWh, M2: "); Serial.print(energy_userr); Serial.print(" kWh.");
    Serial.print(" R1: "); Serial.print(relay1Status ? "ON" : "OFF"); Serial.print(", R2: "); Serial.println(relay2Status ? "ON" : "OFF");
}

void loadPhoneNumbersFromSPIFFS() {
    File file = SPIFFS.open("/phone_numbers.txt", FILE_READ);
    if (!file) {
        Serial.println("Fichier phone_numbers.txt non trouvé, utilisation des numéros par défaut.");
        return;
    }
    int i = 0;
    while (file.available() && i < userCount) {
        userPhoneNumbers[i] = file.readStringUntil('\n');
        userPhoneNumbers[i].trim();
        i++;
    }
    file.close();
    Serial.println("Numéros de téléphone chargés depuis SPIFFS.");
    for (int j = 0; j < userCount; j++) {
      Serial.print("Numéro "); Serial.print(j); Serial.print(": "); Serial.println(userPhoneNumbers[j]);
    }
}

void modifyPhoneNumber(int index, String newNumber) {
    if (index >= 0 && index < userCount) {
        userPhoneNumbers[index] = newNumber;
        savePhoneNumbersToSPIFFS();
        Serial.println("Numéro de téléphone modifié et sauvegardé.");
        lcd.clear();
        lcd.print("Numero "); lcd.print(index); lcd.print(" OK");
        lcd.setCursor(0,1); lcd.print(newNumber);
        delay(2000);
    } else {
        Serial.println("Index invalide pour la modification du numéro.");
        lcd.clear();
        lcd.print("Erreur: Index invalide");
        delay(2000);
    }
    menuState = 0;
    inputBuffer = "";
}

void sendAlertSMS(String message, String phoneNumber) {
    Serial.print("Tentative d'envoi SMS à "); Serial.print(phoneNumber); Serial.print(": "); Serial.println(message);
    sim800.println("AT");
    delay(500);
    if (sim800.find("OK")) {
        sim800.println("AT+CMGF=1");
        delay(100);
        sim800.println("AT+CMGS=\"" + phoneNumber + "\"");
        delay(100);
        sim800.print(message);
        delay(100);
        sim800.write(26);
        delay(3000);
        while(sim800.available()) {
            Serial.write(sim800.read());
        }
        Serial.println("SMS envoyé à " + phoneNumber);
    } else {
        Serial.println("SIM800L non repondant. Verifier connexion.");
    }
}

void readSensors() {
    voltage = capteur_tension.getRmsVoltage();
    current1 = capteur_courant1.getCurrentAC();
    current2 = capteur_courant2.getCurrentAC();
    energy1_instant = (voltage * current1 * (energyInterval / 1000.0)) / 3600000.0;
    energy2_instant = (voltage * current2 * (energyInterval / 1000.0)) / 3600000.0;
    if (energy1_instant < 0) energy1_instant = 0;
    if (energy2_instant < 0) energy2_instant = 0;
    if (energy_user > 0) {
        energy_user -= energy1_instant;
        if (energy_user < 0) energy_user = 0;
    }
    if (energy_userr > 0) {
        energy_userr -= energy2_instant;
        if (energy_userr < 0) energy_userr = 0;
    }
}

void manageRelays() {
    if (energy_user <= SHUTDOWN_THRESHOLD) {
        if (relay1Status == true) {
            digitalWrite(RELAY1_PIN, HIGH);
            relay1Status = false;
            Serial.println("Relais 1 coupé : energy_user epuisee.");
            sendAlertSMS("Energie Maison 1 epuisee. Relais coupe.", userPhoneNumbers[1]);
            if(userCount > 0) sendAlertSMS("Energie Maison 1 epuisee. Relais coupe.", userPhoneNumbers[0]);
            saveEnergyValuesToSPIFFS();
        }
    } else {
        if (relay1Status == false && energy_user > SHUTDOWN_THRESHOLD) {
            // Pour réactivation automatique, décommenter la ligne suivante:
            // digitalWrite(RELAY1_PIN, LOW);
            // relay1Status = true;
            // sendAlertSMS("Energie Maison 1 rechargée. Relais actif.", userPhoneNumbers[1]);
        }
    }
    if (energy_userr <= SHUTDOWN_THRESHOLD) {
        if (relay2Status == true) {
            digitalWrite(RELAY2_PIN, HIGH);
            relay2Status = false;
            Serial.println("Relais 2 coupé : energy_userr epuisee.");
            sendAlertSMS("Energie Maison 2 epuisee. Relais coupe.", userPhoneNumbers[2]);
            if(userCount > 0) sendAlertSMS("Energie Maison 2 epuisee. Relais coupe.", userPhoneNumbers[0]);
            saveEnergyValuesToSPIFFS();
        }
    } else {
        if (relay2Status == false && energy_userr > SHUTDOWN_THRESHOLD) {
            // Pour réactivation automatique, décommenter la ligne suivante:
            // digitalWrite(RELAY2_PIN, LOW);
            // relay2Status = true;
            // sendAlertSMS("Energie Maison 2 rechargée. Relais actif.", userPhoneNumbers[2]);
        }
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
  scanWiFiNetworks();
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(1000);
  Serial.println("\nTentative de connexion...");
  lcd.clear();
  lcd.print("Connexion WiFi...");
  int attempts = 0;
  const int MAX_WIFI_RETRIES_LOCAL = 3; // Limite à 3 tentatives
  while (WiFi.status() != WL_CONNECTED && attempts < MAX_WIFI_RETRIES_LOCAL) {
    Serial.print("Tentative ");
    Serial.print(attempts + 1);
    Serial.print("/");
    Serial.println(MAX_WIFI_RETRIES_LOCAL);
    WiFi.begin(ssid, password);
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
      Serial.print("Force du signal (RSSI): ");
      Serial.println(WiFi.RSSI());
      lcd.clear();
      lcd.print("WiFi connecte");
      lcd.setCursor(0, 1);
      lcd.print(WiFi.localIP());
      isOnline = true;
      return;
    }
    attempts++;
    if (attempts < MAX_WIFI_RETRIES_LOCAL) {
      Serial.println("Échec de la connexion, nouvelle tentative...");
      lcd.clear();
      lcd.print("Tentative ");
      lcd.print(attempts + 1);
      lcd.print("/");
      lcd.print(MAX_WIFI_RETRIES_LOCAL);
      delay(WIFI_RETRY_DELAY);
    }
  }
  // Si toujours pas connecté après 3 tentatives
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("\nÉchec de la connexion WiFi après 3 tentatives");
    lcd.clear();
    lcd.print("Mode Hors Ligne");
    lcd.setCursor(0, 1);
    lcd.print("WiFi indisponible");
    isOnline = false;
    lastOfflineSave = millis(); // Pour forcer la sauvegarde hors ligne si besoin
  }
}

void sendDataToServer() {
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n=== Envoi des données au serveur ===");
    int retryCount = 0;
    bool success = false;
    while (!success && retryCount < MAX_API_RETRIES) {
      WiFiClientSecure client;
      client.setInsecure(); // <-- Ajoute ceci pour ignorer le certificat (pas sécurisé)
      HTTPClient https;
      Serial.println("\nTentative de connexion à l'API...");
      String url = String(BASE_API_URL) + DATA_SEND_PATH;
      Serial.print("URL : ");
      Serial.println(url);
      https.begin(client, url);
      https.addHeader("Content-Type", "application/json");
      https.addHeader("x-api-key", apiKey);
      https.addHeader("Accept", "application/json");
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
      Serial.println("   Content-Type: application/json");
      Serial.println("   x-api-key: " + String(apiKey));
      Serial.println("   Accept: application/json");
      Serial.println("Données envoyées :");
      Serial.println(jsonData);
      Serial.println("\nEnvoi de la requête...");
      int httpResponseCode = https.POST(jsonData);
      if (httpResponseCode > 0) {
        String response = https.getString();
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
        }
      } else {
        Serial.println("\nErreur de connexion :");
        Serial.println("Code : " + String(httpResponseCode));
        Serial.println("Erreur : " + https.errorToString(httpResponseCode));
      }
      https.end();
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
      lcd.clear();
      lcd.print("Erreur envoi");
      lcd.setCursor(0, 1);
      lcd.print("Donnees sauvegardees");
      saveEnergyValuesToSPIFFS();
    }
  } else {
    Serial.println("\nPas de connexion WiFi, tentative de reconnexion...");
    lcd.clear();
    lcd.print("Pas de WiFi");
    connectToWiFi();
  }
}

void checkServerCommands() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String commandUrl = String(BASE_API_URL) + COMMANDS_FETCH_PATH + "?deviceId=" + deviceId;
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
      } else {
        Serial.print("Erreur de désérialisation JSON des commandes: ");
        Serial.println(error.c_str());
      }
    } else {
      Serial.print("Erreur HTTP lors de la récupération des commandes: ");
      Serial.println(httpResponseCode);
    }
    http.end();
  }
}

void processCommand(const char* commandType, const JsonObject& parameters) {
  if (strcmp(commandType, "recharge_energy") == 0) {
    float energyAmount = parameters["energy_amount"] | 0.0;
    int targetUser = parameters["user_id"] | 0;
    Serial.print("Commande de recharge reçue: ");
    Serial.print(energyAmount);
    Serial.print(" kWh pour Maison ");
    Serial.println(targetUser);
    if (targetUser == 1) {
      energy_user += energyAmount;
      Serial.print("Nouvelle énergie maison 1: ");
      Serial.println(energy_user);
      lcd.clear();
      lcd.print("M1 Recharged: ");
      lcd.print(energyAmount);
      lcd.print(" kWh");
      lcd.setCursor(0,1);
      lcd.print("Total: ");
      lcd.print(energy_user, 1);
      delay(3000);
      saveEnergyValuesToSPIFFS();
      if(energy_user > SHUTDOWN_THRESHOLD && !relay1Status) {
        digitalWrite(RELAY1_PIN, LOW);
        relay1Status = true;
        Serial.println("Relais 1 réactivé par commande.");
        sendAlertSMS("Energie Maison 1 rechargée. Relais actif par commande.", userPhoneNumbers[1]);
      }
    } else if (targetUser == 2) {
      energy_userr += energyAmount;
      Serial.print("Nouvelle énergie maison 2: ");
      Serial.println(energy_userr);
      lcd.clear();
      lcd.print("M2 Recharged: ");
      lcd.print(energyAmount);
      lcd.print(" kWh");
      lcd.setCursor(0,1);
      lcd.print("Total: ");
      lcd.print(energy_userr, 1);
      delay(3000);
      saveEnergyValuesToSPIFFS();
      if(energy_userr > SHUTDOWN_THRESHOLD && !relay2Status) {
        digitalWrite(RELAY2_PIN, LOW);
        relay2Status = true;
        Serial.println("Relais 2 réactivé par commande.");
        sendAlertSMS("Energie Maison 2 rechargée. Relais actif par commande.", userPhoneNumbers[2]);
      }
    } else {
        Serial.println("Commande de recharge reçue pour un utilisateur inconnu.");
    }
  } else if (strcmp(commandType, "set_relay_status") == 0) {
    int targetUser = parameters["user_id"] | 0;
    bool status = parameters["status"] | false;
    Serial.print("Commande relais reçue pour Maison ");
    Serial.print(targetUser);
    Serial.print(": ");
    Serial.println(status ? "ON" : "OFF");
    if (targetUser == 1) {
      digitalWrite(RELAY1_PIN, status ? LOW : HIGH);
      relay1Status = status;
      lcd.clear();
      lcd.print("R1: ");
      lcd.print(status ? "ON " : "OFF");
      delay(2000);
      saveEnergyValuesToSPIFFS();
    } else if (targetUser == 2) {
      digitalWrite(RELAY2_PIN, status ? LOW : HIGH);
      relay2Status = status;
      lcd.clear();
      lcd.print("R2: ");
      lcd.print(status ? "ON" : "OFF");
      delay(2000);
      saveEnergyValuesToSPIFFS();
    } else {
        Serial.println("Commande relais reçue pour un utilisateur inconnu.");
    }
  }
}

String getTimestamp() {
  time_t now;
  struct tm timeinfo;
  time(&now);
  localtime_r(&now, &timeinfo);
  char buffer[20];
  strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%S", &timeinfo);
  return String(buffer);
}

void updateLCD() {
    if (menuState == 0) {
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print(isOnline ? "En ligne" : "Hors ligne");
        lcd.setCursor(10, 0);
        String ts = getTimestamp();
        if (ts.length() >= 16) {
          lcd.print(ts.substring(11, 16));
        }
        lcd.setCursor(0, 1);
        lcd.print("M1: ");
        if (energy_user < 1000.0) lcd.print(energy_user, 1);
        else lcd.print((int)energy_user);
        lcd.print(" kWh");
        lcd.setCursor(0, 2);
        lcd.print("M2: ");
        if (energy_userr < 1000.0) lcd.print(energy_userr, 1);
        else lcd.print((int)energy_userr);
        lcd.print(" kWh");
        lcd.setCursor(0, 3);
        lcd.print("R1:");
        lcd.print(relay1Status ? "ON " : "OFF");
        lcd.print(" R2:");
        lcd.print(relay2Status ? "ON " : "OFF");
    }
}

void handleKeypadInput() {
    char key = keypad.getKey();
    if (key) {
        Serial.print("Touche pressée : ");
        Serial.println(key);
        if (isPasswordMode) {
            handlePasswordInput(key);
            return;
        }
        switch(menuState) {
            case 0:
                if (key == 'M') {
                    menuState = 1;
                    showMainMenu();
                }
                else if (key == '1') {
                    previousMenuBeforePassword = 2;
                    enterPasswordMode();
                }
                else if (key == '2') {
                    previousMenuBeforePassword = 3;
                    enterPasswordMode();
                }
                break;
            case 1:
                handleMainMenu(key);
                break;
            case 2:
                if (key >= '0' && key <= '9' || key == '.') {
                    inputBuffer += key;
                    lcd.setCursor(0,2);
                    lcd.print("                   ");
                    lcd.setCursor(0,2);
                    lcd.print(inputBuffer);
                } else if (key == 'A') {
                    float rechargeAmount = inputBuffer.toFloat();
                    if (rechargeAmount > 0) {
                        energy_user += rechargeAmount;
                        saveEnergyValuesToSPIFFS();
                        lcd.clear();
                        lcd.print("M1 Recharged:");
                        lcd.setCursor(0,1);
                        lcd.print(rechargeAmount, 1);
                        lcd.print(" kWh. New Total:");
                        lcd.setCursor(0,2);
                        lcd.print(energy_user, 1);
                        lcd.print(" kWh");
                        if (!relay1Status && energy_user > SHUTDOWN_THRESHOLD) {
                          digitalWrite(RELAY1_PIN, LOW);
                          relay1Status = true;
                          lcd.setCursor(0,3);
                          lcd.print("Relais 1 Actif");
                          sendAlertSMS("Energie Maison 1 rechargée de " + String(rechargeAmount,1) + " kWh. Relais actif. Nouveau solde: " + String(energy_user,1) + " kWh.", userPhoneNumbers[1]);
                        }
                    } else {
                        lcd.clear();
                        lcd.print("Valide: > 0");
                    }
                    delay(2000);
                    inputBuffer = "";
                    menuState = 0;
                } else if (key == 'D') {
                    inputBuffer = "";
                    menuState = 0;
                    updateLCD();
                }
                break;
            case 3:
                if (key >= '0' && key <= '9' || key == '.') {
                    inputBuffer += key;
                    lcd.setCursor(0,2);
                    lcd.print("                   ");
                    lcd.setCursor(0,2);
                    lcd.print(inputBuffer);
                } else if (key == 'A') {
                    float rechargeAmount = inputBuffer.toFloat();
                    if (rechargeAmount > 0) {
                        energy_userr += rechargeAmount;
                        saveEnergyValuesToSPIFFS();
                        lcd.clear();
                        lcd.print("M2 Recharged:");
                        lcd.setCursor(0,1);
                        lcd.print(rechargeAmount, 1);
                        lcd.print(" kWh. New Total:");
                        lcd.setCursor(0,2);
                        lcd.print(energy_userr, 1);
                        lcd.print(" kWh");
                        if (!relay2Status && energy_userr > SHUTDOWN_THRESHOLD) {
                          digitalWrite(RELAY2_PIN, LOW);
                          relay2Status = true;
                          lcd.setCursor(0,3);
                          lcd.print("Relais 2 Actif");
                          sendAlertSMS("Energie Maison 2 rechargée de " + String(rechargeAmount,1) + " kWh. Relais actif. Nouveau solde: " + String(energy_userr,1) + " kWh.", userPhoneNumbers[2]);
                        }
                    } else {
                        lcd.clear();
                        lcd.print("Valide: > 0");
                    }
                    delay(2000);
                    inputBuffer = "";
                    menuState = 0;
                } else if (key == 'D') {
                    inputBuffer = "";
                    menuState = 0;
                    updateLCD();
                }
                break;
            case 4:
                handleRelayMenu(key);
                break;
            case 5:
                handleConfigPhoneMenu(key);
                break;
        }
    }
}

void showMainMenu() {
    lcd.clear();
    lcd.setCursor(0,0); lcd.print("--- Menu Principal ---");
    lcd.setCursor(0,1); lcd.print("1. Recharge M1");
    lcd.setCursor(0,2); lcd.print("2. Recharge M2");
    lcd.setCursor(0,3); lcd.print("3. Gerer Relais");
}

void handleMainMenu(char key) {
    if (key == '1') {
        previousMenuBeforePassword = 2;
        enterPasswordMode();
    } else if (key == '2') {
        previousMenuBeforePassword = 3;
        enterPasswordMode();
    } else if (key == '3') {
        previousMenuBeforePassword = 4;
        enterPasswordMode();
    } else if (key == '4') {
        previousMenuBeforePassword = 5;
        enterPasswordMode();
    } else if (key == 'D') {
        menuState = 0;
        updateLCD();
    }
}

void showRelayMenu() {
    lcd.clear();
    lcd.setCursor(0,0); lcd.print("-- Gerer Relais --");
    lcd.setCursor(0,1); lcd.print("1. R1 ON/OFF");
    lcd.setCursor(0,2); lcd.print("2. R2 ON/OFF");
    lcd.setCursor(0,3); lcd.print("D. Retour");
}

void handleRelayMenu(char key) {
    if (key == '1') {
        relay1Status = !relay1Status;
        digitalWrite(RELAY1_PIN, relay1Status ? LOW : HIGH);
        saveEnergyValuesToSPIFFS();
        lcd.clear();
        lcd.print("Relais 1: "); lcd.print(relay1Status ? "ON" : "OFF");
        delay(1500);
        showRelayMenu();
    } else if (key == '2') {
        relay2Status = !relay2Status;
        digitalWrite(RELAY2_PIN, relay2Status ? LOW : HIGH);
        saveEnergyValuesToSPIFFS();
        lcd.clear();
        lcd.print("Relais 2: "); lcd.print(relay2Status ? "ON" : "OFF");
        delay(1500);
        showRelayMenu();
    } else if (key == 'D') {
        menuState = 1;
        showMainMenu();
    }
}

void showConfigPhoneMenu() {
    lcd.clear();
    lcd.setCursor(0,0); lcd.print("-- Config Numeros --");
    lcd.setCursor(0,1); lcd.print("1. Owner: "); lcd.print(userPhoneNumbers[0]);
    lcd.setCursor(0,2); lcd.print("2. M1: "); lcd.print(userPhoneNumbers[1]);
    lcd.setCursor(0,3); lcd.print("3. M2: "); lcd.print(userPhoneNumbers[2]);
}

void handleConfigPhoneMenu(char key) {
    if (key >= '1' && key <= '3') {
        int userIndex = key - '1';
        lcd.clear();
        lcd.print("New Num for User "); lcd.print(userIndex);
        lcd.setCursor(0,1); lcd.print("Entrez N° (A=OK, D=Annuler):");
        lcd.setCursor(0,2); lcd.print(inputBuffer);
        menuState = 6 + userIndex;
        inputBuffer = "";
    } else if (key == 'D') {
        menuState = 1;
        showMainMenu();
    }
}

void enterPasswordMode() {
    isPasswordMode = true;
    enteredPassword = "";
    lcd.clear();
    lcd.setCursor(0,0); lcd.print("Entrez mot de passe:");
    lcd.setCursor(0,1); lcd.print("PIN: ");
    lcd.setCursor(5,1); lcd.print("____");
}

void handlePasswordInput(char key) {
    if (key >= '0' && key <= '9' && enteredPassword.length() < 4) {
        enteredPassword += key;
        lcd.setCursor(5,1);
        for (int i = 0; i < enteredPassword.length(); i++) {
            lcd.print("*");
        }
        for (int i = enteredPassword.length(); i < 4; i++) {
            lcd.print("_");
        }
    } else if (key == 'A') {
        if (enteredPassword.length() == 4) {
            verifyPassword();
        } else {
            lcd.setCursor(0,2);
            lcd.print("PIN incomplet !");
            delay(1000);
            lcd.setCursor(0,2);
            lcd.print("                ");
            lcd.setCursor(5,1);
            for (int i = 0; i < enteredPassword.length(); i++) {
                lcd.print("*");
            }
            for (int i = enteredPassword.length(); i < 4; i++) {
                lcd.print("_");
            }
        }
    } else if (key == 'D') {
        clearPassword();
        isPasswordMode = false;
        menuState = 0;
        updateLCD();
    }
}

void clearPassword() {
    enteredPassword = "";
    lcd.setCursor(5,1);
    lcd.print("____");
}

void verifyPassword() {
    isPasswordMode = false;
    if (enteredPassword == ownerPassword) {
        lcd.clear();
        lcd.print("Acces accorde!");
        delay(1000);
        if (previousMenuBeforePassword == 2) {
            menuState = 2;
            lcd.clear();
            lcd.print("M1: Solde actuel:");
            lcd.setCursor(0,1);
            lcd.print(energy_user, 1);
            lcd.print(" kWh");
            lcd.setCursor(0,2);
            lcd.print("Saisir recharge (kWh):");
        } else if (previousMenuBeforePassword == 3) {
            menuState = 3;
            lcd.clear();
            lcd.print("M2: Solde actuel:");
            lcd.setCursor(0,1);
            lcd.print(energy_userr, 1);
            lcd.print(" kWh");
            lcd.setCursor(0,2);
            lcd.print("Saisir recharge (kWh):");
        } else if (previousMenuBeforePassword == 4) {
            menuState = 4;
            showRelayMenu();
        } else if (previousMenuBeforePassword == 5) {
            menuState = 5;
            showConfigPhoneMenu();
        }
    } else {
        lcd.clear();
        lcd.print("Mot de passe incorrect!");
        delay(1500);
        menuState = 0;
    }
    clearPassword();
    updateLCD();
}

void checkWiFiConnection() {
  if (WiFi.status() != WL_CONNECTED && isOnline) {
    Serial.println("WiFi déconnecté. Tentative de reconnexion...");
    lcd.clear();
    lcd.print("WiFi Deconnecte!");
    isOnline = false;
    connectToWiFi();
  } else if (WiFi.status() == WL_CONNECTED && !isOnline) {
    Serial.println("WiFi rétabli.");
    lcd.clear();
    lcd.print("WiFi Reconnecte!");
    isOnline = true;
    delay(1000);
    updateLCD();
  }
}

void saveOfflineData() {
  Serial.println("Sauvegarde des données en mode hors ligne...");
  saveEnergyValuesToSPIFFS();
  lcd.clear();
  lcd.print("Donnees Sauvegardees");
  lcd.setCursor(0,1);
  lcd.print("Mode Hors Ligne");
  delay(1500);
}

void checkAlerts() {
    if (energy_user <= ALERT_THRESHOLD && energy_user > SHUTDOWN_THRESHOLD && !maison1AlertSent) {
        sendAlertSMS("ATTENTION: Energie Maison 1 faible (" + String(energy_user, 1) + " kWh).", userPhoneNumbers[1]);
        if(userCount > 0) sendAlertSMS("ATTENTION: Energie Maison 1 faible (" + String(energy_user, 1) + " kWh).", userPhoneNumbers[0]);
        maison1AlertSent = true;
    } else if (energy_user > ALERT_THRESHOLD && maison1AlertSent) {
        maison1AlertSent = false;
    }
    if (energy_userr <= ALERT_THRESHOLD && energy_userr > SHUTDOWN_THRESHOLD && !maison2AlertSent) {
        sendAlertSMS("ATTENTION: Energie Maison 2 faible (" + String(energy_userr, 1) + " kWh).", userPhoneNumbers[2]);
        if(userCount > 0) sendAlertSMS("ATTENTION: Energie Maison 2 faible (" + String(energy_userr, 1) + " kWh).", userPhoneNumbers[0]);
        maison2AlertSent = true;
    } else if (energy_userr > ALERT_THRESHOLD && maison2AlertSent) {
        maison2AlertSent = false;
    }
}