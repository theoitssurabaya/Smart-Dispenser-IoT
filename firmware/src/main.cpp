#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <NewPing.h>
#include "HX711.h"

// --- KREDENSIAL ---
// Ganti dengan kredensial Anda
const char* ssid = "xxx";
const char* password = "xxx";
const char* mqtt_server = "xxx";
const int mqtt_port = 8883;
const char* mqtt_user = "xxx";
const char* mqtt_pass = "xxx";

// --- PIN HARDWARE ---
#define PUMP_PIN 13      
#define FLOW_PIN 14     
#define TRIG_PIN 5      
#define ECHO_PIN 18     
#define LOADCELL_DOUT_PIN 4
#define LOADCELL_SCK_PIN  2

// --- KALIBRASI ---
float flowCalibrationFactor = 5880.0; 
float weightCalibrationFactor = 60.0; 

// --- OBJEK ---
NewPing sonar(TRIG_PIN, ECHO_PIN, 50); 
WiFiClientSecure espClient;
PubSubClient client(espClient);
HX711 scale;

// --- VARIABEL ---
volatile long pulseCount = 0;
bool isFilling = false;
int targetMl = 0;
String currentUid = "";
unsigned long totalMilliLitres = 0;
unsigned long lastDebugMillis = 0;
unsigned long lastLevelUpdate = 0;

void IRAM_ATTR pulseCounter() { pulseCount++; }

void stopAndReport(bool success) {
  digitalWrite(PUMP_PIN, LOW);
  isFilling = false;
  
  long sisaAirGalon = scale.get_units(5); 
  if (sisaAirGalon < 0) sisaAirGalon = 0; 

  JsonDocument doc;
  doc["uid"] = currentUid;
  doc["used_ml"] = totalMilliLitres; 
  doc["remaining_ml"] = sisaAirGalon; 
  doc["status"] = success ? "SUCCESS" : "ABORTED";
  
  char buffer[128];
  serializeJson(doc, buffer);
  client.publish("dispenser/report", buffer);

  Serial.println("\n[STOP] Laporan Terkirim.");
  Serial.printf("Keluar: %lu ml | Sisa Galon: %ld ml (gram)\n", totalMilliLitres, sisaAirGalon);

  pulseCount = 0;
  totalMilliLitres = 0;
  lastDebugMillis = 0;
}

void callback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (int i = 0; i < length; i++) { message += (char)payload[i]; }
  
  JsonDocument doc;
  deserializeJson(doc, message);

  if (doc["action"] == "START") {
    targetMl = doc["target"];
    currentUid = doc["uid"].as<String>();
    
    int jarak = sonar.ping_cm();
    Serial.printf("[START] Jarak Gelas: %d cm\n", jarak);

    if (jarak > 0 && jarak < 20) {
      isFilling = true;
      pulseCount = 0;
      totalMilliLitres = 0;
      lastDebugMillis = millis();
      
      digitalWrite(PUMP_PIN, HIGH);
      Serial.println("[SYSTEM] Pompa ON...");
    } else {
      Serial.println("[REJECT] Gelas tidak ada.");
      stopAndReport(false);
    }
  }
}

void sendRealtimeLevel() {
  if (scale.is_ready()) {
    long currentWeight = scale.get_units(3);
    if (currentWeight < 0) currentWeight = 0;

    JsonDocument doc;
    doc["status"] = "LEVEL_UPDATE"; 
    doc["remaining_ml"] = currentWeight;
    
    char buffer[128];
    serializeJson(doc, buffer);
    client.publish("dispenser/report", buffer);
  }
}

void reconnect() {
  while (!client.connected()) {
    String clientId = "ESP32_Disp_" + String(random(0xffff), HEX);
    if (client.connect(clientId.c_str(), mqtt_user, mqtt_pass)) {
      client.subscribe("dispenser/cmd");
    } else {
      delay(5000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  
  pinMode(PUMP_PIN, OUTPUT);
  digitalWrite(PUMP_PIN, LOW);
  
  pinMode(FLOW_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(FLOW_PIN), pulseCounter, FALLING);

  Serial.println("Inisialisasi Load Cell...");
  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  scale.set_scale(weightCalibrationFactor);
  scale.tare(); 

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) delay(500);

  espClient.setInsecure(); 
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);
}

void loop() {
  if (!client.connected()) reconnect();
  client.loop();

  if (millis() - lastLevelUpdate > 5000) { 
    sendRealtimeLevel();
    lastLevelUpdate = millis();
  }

  if (isFilling) {
    totalMilliLitres = (pulseCount * 1000) / flowCalibrationFactor; 
    
    if (millis() - lastDebugMillis > 1000) {
      int d = sonar.ping_cm();
      sendRealtimeLevel(); 
      
      Serial.printf("Filling... %lu / %d ml | Jarak: %d cm\n", totalMilliLitres, targetMl, d);
      
      if (d > 25 || d == 0) {
        Serial.println("[SAFETY] Gelas Hilang!");
        stopAndReport(false);
      }
      lastDebugMillis = millis();
    }

    if (totalMilliLitres >= (unsigned long)targetMl) {
      stopAndReport(true);
    }
  }
}