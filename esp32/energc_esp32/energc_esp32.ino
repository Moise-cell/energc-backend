/*
 * EnergC - ESP32 Controller
 * 
 * Ce script gère :
 * - Un afficheur LCD 16x2 (I2C)
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

// Configuration WiFi
const char* ssid = "MoiseMb";          // Nom du réseau WiFi
const char* password = "moise1234";    // Mot de passe du réseau WiFi

// Configuration de l'appareil
String deviceId = "esp32_maison1"; // Changer en "esp32_maison2" pour la seconde maison
const int EEPROM_SIZE = 512;
// Configuration API
const char* apiUrl = "http://<votre-serveur-api>:3000/api/data"; // Remplacez par l'URL de votre API REST
const char* apiKey = "VOTRE_API_KEY"; // Remplacez par votre clé API
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
HardwareSerial sim800(1); // Utilisation du port série matériel UART1
// Seuils d'alerte pour l'énergie
const float ALERT_THRESHOLD = 1.0; // Alerte lorsque l'énergie restante est inférieure à 1 kWh
const float SHUTDOWN_THRESHOLD = 0.1; // Coupure du relais lorsque l'énergie restante est inférieure à 0.1 kWh
// Configuration du clavier 4x4
const byte ROWS = 4;
const byte COLS = 4;
char keys[ROWS][COLS] = {
  {'1', '2', '3', 'A'},
  {'4', '5', '6', 'B'},
  {'7', '8', '9', 'C'},
  {'*', '0', '#', 'D'}
};
byte rowPins[ROWS] = {13, 12, 14, 27}; // Broches connectées aux lignes du clavier
byte colPins[COLS] = {26, 25, 33, 32};    // Broches connectées aux colonnes du clavier
// Initialisation des objets
LiquidCrystal_I2C lcd(0x27, 20, 4); // Remplacez 0x27 par l'adresse détectée
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);
// Variables globales
float voltage = 0.0;
float current1 = 0.0;
float current2 = 0.0;
float energy1 = 0.0;
float energy2 = 0.0;
bool relay1Status = false;
bool relay2Status = false;
unsigned long lastDataSendTime = 0;
unsigned long lastCommandCheckTime = 0;
unsigned long lastMeasurementTime = 0;
unsigned long lastAlertTime = 0;
const unsigned long alertInterval = 60000; // 1 minute
String currentMessage = "";
int menuState = 0;
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

// Facteurs de conversion
#define FACTOR_VOLTAGE 0.0061 // Exemple : Facteur de conversion pour le capteur de tension
#define FACTOR_CURRENT 0.01   // Exemple : Facteur de conversion pour le capteur ACS712
#define TIME_INTERVAL 1       // Intervalle de temps en secondes entre les lectures

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
    voltage = analogRead(VOLTAGE_SENSOR_PIN) * FACTOR_VOLTAGE;
    current1 = analogRead(CURRENT_SENSOR1_PIN) * FACTOR_CURRENT;
    current2 = analogRead(CURRENT_SENSOR2_PIN) * FACTOR_CURRENT;
    energy1 += current1 * voltage * TIME_INTERVAL;
    energy2 += current2 * voltage * TIME_INTERVAL;
}

void manageRelays() {
    if (energy1 < SHUTDOWN_THRESHOLD) {
        digitalWrite(RELAY1_PIN, LOW);
        relay1Status = false;
    } else {
        digitalWrite(RELAY1_PIN, HIGH);
        relay1Status = true;
    }
    // Idem pour le relais 2
}

void sendDataToDatabase() {
    if (WiFi.status() == WL_CONNECTED) {
        HTTPClient http;
        http.begin(apiUrl);
        http.addHeader("Content-Type", "application/json");
        http.addHeader("Authorization", apiKey);

        StaticJsonDocument<200> doc;
        doc["deviceId"] = deviceId;
        doc["voltage"] = voltage;
        doc["current1"] = current1;
        doc["current2"] = current2;
        doc["energy1"] = energy1;
        doc["energy2"] = energy2;

        String jsonData;
        serializeJson(doc, jsonData);

        int httpResponseCode = http.POST(jsonData);
        if (httpResponseCode > 0) {
            Serial.println("Données envoyées avec succès.");
        } else {
            Serial.println("Erreur lors de l'envoi des données.");
        }
        http.end();
    }
}

void updateLCD() {
    lcd.clear(); // Efface l'écran
    lcd.setCursor(0, 0);
    lcd.print("Voltage: ");
    lcd.print(voltage, 2); // Affiche la tension avec 2 décimales
    lcd.print(" V");

    lcd.setCursor(0, 1);
    lcd.print("I1: ");
    lcd.print(current1, 2); // Courant Maison 1
    lcd.print(" A");

    lcd.setCursor(0, 2);
    lcd.print("I2: ");
    lcd.print(current2, 2); // Courant Maison 2
    lcd.print(" A");

    lcd.setCursor(0, 3);
    lcd.print("E1: ");
    lcd.print(energy1, 2); // Énergie Maison 1
    lcd.print(" kWh");
}

void handleKeypadInput() {
    char key = keypad.getKey();
    if (key) {
        Serial.println("Touche pressée : " + String(key));
    }
}

void setup() {
  Wire.begin();
  Serial.begin(115200);
  Serial.println("\nI2C Scanner");
  for (uint8_t address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      Serial.print("I2C device found at address 0x");
      Serial.println(address, HEX);
      delay(500);
    }
  }
  Serial.println("Scan complete.");

    if (!SPIFFS.begin(true)) {
        Serial.println("Erreur : SPIFFS non initialisé.");
        return;
    }

    Serial.println("SPIFFS initialisé avec succès.");

    // Charger les numéros de téléphone depuis SPIFFS
    loadPhoneNumbersFromSPIFFS();

    // Charger les données d'énergie depuis SPIFFS
    loadEnergyValuesFromSPIFFS();

    // Initialisation de l'écran LCD
    lcd.begin();
    lcd.backlight();
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Hello, World!");

    // Autres initialisations...

    Serial.println("Test du clavier 4x4");
}

void loop() {
    readSensors();       // Lire les capteurs
    manageRelays();      // Gérer les relais
    sendDataToDatabase(); // Envoyer les données à la base de données
    handleKeypadInput(); // Gérer les entrées du clavier
    updateLCD();         // Mettre à jour l'écran LCD
    delay(1000);         // Attendre 1 seconde avant la prochaine itération
}
