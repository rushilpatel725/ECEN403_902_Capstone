#include <WiFi.h>
#include <HTTPClient.h>

#define WIFI_SSID "Hee Hee Hoo Hoo Ha Ha"
#define WIFI_PASSWORD "beepboop"

#define WATER_SENSOR_PIN 32
#define FIREBASE_URL "https://iot-water-leak-default-rtdb.firebaseio.com/leak_readings.json"


void sendLeakStatus(int status);

void setup() {
  Serial.begin(115200);

  // Connect to Wi-Fi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi...");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");
}

void loop() {
  int leakDetected = analogRead(WATER_SENSOR_PIN);

  leakDetected = leakDetected/5;
  
  sendLeakStatus(leakDetected);  // Send leak status to Firebase

  delay(5000);  // Send every 5 seconds
}

void sendLeakStatus(int status) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(FIREBASE_URL);
    http.addHeader("Content-Type", "application/json");  //JSON

    String payload = String("{\"leak\": ") + status + "}";
    int responseCode = http.POST(payload);  // Send PUT request to Firebase

    Serial.print("Response Code: ");
    Serial.println(responseCode);  // Print response code
    Serial.println(http.getString());

    http.end();  // End the HTTP connection
  } else {
    Serial.println("Not connected");
  }
}
