#include <WiFi.h>
#include <HTTPClient.h>
#include <time.h>

// Wi-Fi credentials
#define WIFI_SSID "Hee Hee Hoo Hoo Ha Ha"
#define WIFI_PASSWORD "beepboop"

// Pins and Firebase URL
#define WATER_SENSOR_PIN 33
#define FIREBASE_URL "https://iot-water-leak-default-rtdb.firebaseio.com/leak_readings.json"

// Central Time offset (seconds)
#define GMT_OFFSET_SEC   -21600   // -6 hours
#define DAYLIGHT_OFFSET_SEC 3600  // +1 hour during DST

void sendLeakStatus(int status);

void setup() {
  Serial.begin(115200);

  // Connect to Wi-Fi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");

  // Configure NTP time with Central Time offset
  configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, "pool.ntp.org", "time.nist.gov");

  Serial.print("Waiting for NTP time sync");
  struct tm timeinfo;
  while (!getLocalTime(&timeinfo)) {
    Serial.print(".");
    delay(500);
  }
  Serial.println("\nTime synchronized!");
}

void loop() {
  int leakDetected = analogRead(WATER_SENSOR_PIN);  // raw ADC (0–4095)
  
  sendLeakStatus(leakDetected);

  delay(5000);  // send every 5 seconds
}

void sendLeakStatus(int status) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(FIREBASE_URL);
    http.addHeader("Content-Type", "application/json");

    // Get current Central time
    struct tm timeinfo;
    getLocalTime(&timeinfo);

    char timeString[30];
    strftime(timeString, sizeof(timeString), "%Y-%m-%d %H:%M:%S", &timeinfo);

    // Build JSON payload
    String payload = "{";
    payload += "\"leak\": " + String(status) + ",";
    payload += "\"time\": \"" + String(timeString) + "\"";
    payload += "}";

    Serial.print("Payload: ");
    Serial.println(payload);

    int responseCode = http.PUT(payload);

    Serial.print("Response Code: ");
    Serial.println(responseCode);
    Serial.println("Response Body: " + http.getString());

    http.end();
  } else {
    Serial.println("Not connected");
  }
}
