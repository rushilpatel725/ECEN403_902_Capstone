/*
#include <WiFi.h>
#include <HTTPClient.h>
#include <esp_now.h>
#include <time.h>

// Wi-Fi & Firebase
#define WIFI_SSID "TAMU_IoT"
#define FIREBASE_URL "https://iot-water-leak-default-rtdb.firebaseio.com/leak_readings.json"

// Time settings
#define GMT_OFFSET_SEC     -21600
#define DAYLIGHT_OFFSET_SEC 3600

// ESP-NOW message
typedef struct struct_message {
  int id;
  float flow_Lmin;
} struct_message;

struct_message incomingData;

// Globals
float remote1_flow = 0.0;
float remote2_flow = 0.0;
float local_flow = 0.0;

#define LOCAL_SENSOR_PIN 33
int count = 0;
int memory = 0;


// Function prototypes
void sendLeakStatus(float localFlow, float remote1Flow, float remote2Flow);
void OnDataRecv(const uint8_t * mac, const uint8_t *incoming, int len);

void setup() {
  Serial.begin(115200);
  pinMode(LOCAL_SENSOR_PIN, INPUT);
  
  // Wi-Fi
  WiFi.begin(WIFI_SSID);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }
  Serial.println("\nWi-Fi connected");

  // ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }
  esp_now_register_recv_cb(OnDataRecv);

  // Time sync
  configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, "pool.ntp.org", "time.nist.gov");

  Serial.println("Receiver ready for multiple sensors...");
}

void loop() {
  int adc = analogRead(LOCAL_SENSOR_PIN);
  if (adc > 110) {
    if (memory == 0) count++;
    memory = 1;
  } else {
    if (memory == 1) count++;
    memory = 0;
  }

  local_flow = (count * 0.001) * (60.0 / 2.0); // L/min

  if (count > 1000){
    sendLeakStatus(local_flow, remote1_flow, remote2_flow);
  }
}

void OnDataRecv(const uint8_t * mac, const uint8_t *incoming, int len) {
  if (len != sizeof(struct_message)) return; // Safety check

  memcpy(&incomingData, incoming, sizeof(incomingData));

  if (incomingData.id == 1) remote1_flow = incomingData.flow_Lmin;
  else if (incomingData.id == 2) remote2_flow = incomingData.flow_Lmin;

  Serial.printf("Received ID %d: %.2f L/min\n", incomingData.id, incomingData.flow_Lmin);
}

void sendLeakStatus(float localFlow, float remote1Flow, float remote2Flow) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(FIREBASE_URL);
    http.addHeader("Content-Type", "application/json");

    struct tm timeinfo;
    getLocalTime(&timeinfo);
    char timeString[30];
    strftime(timeString, sizeof(timeString), "%Y-%m-%d %H:%M:%S", &timeinfo);

    String payload = "{";
    payload += "\"local_sensor\": " + String(localFlow, 2) + ",";
    payload += "\"remote1_sensor\": " + String(remote1Flow, 2) + ",";
    payload += "\"remote2_sensor\": " + String(remote2Flow, 2) + ",";
    payload += "\"time\": \"" + String(timeString) + "\"";
    payload += "}";

    Serial.println("Uploading: " + payload);
    int responseCode = http.PUT(payload);
    Serial.printf("Response Code: %d\n", responseCode);
    Serial.println("Response Body: " + http.getString());
    http.end();
  } else {
    Serial.println("Wi-Fi not connected!");
  }
}
*/