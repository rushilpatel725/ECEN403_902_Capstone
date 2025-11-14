/*
#include <esp_now.h>
#include <WiFi.h>

// --- !! IMPORTANT !! ---
// 1. Get the MAC address from your Gateway's Serial Monitor output.
// 2. Paste that 6-part MAC address here.
//    (Example: {0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF})
uint8_t gateway_mac[] = {0x80, 0xF3, 0xDA, 0x54, 0x66, 0x64};

// --- Sensor Pin ---
// Make sure this is the correct pin for your remote sensors
#define LOCAL_SENSOR_PIN 33 

// --- Globals for Local Sensor ---
float current_flow_LPM = 0.0; // Holds the most recently calculated flow rate
int pulse_count = 0;          // Pulse count *for the current interval*
int last_memory = 0;          // Memory for edge detection

// --- Timer ---
unsigned long last_calc_time = 0;
// This controls how often this remote sensor calculates and SENDS
const long CALC_AND_SEND_INTERVAL = 2000; // Calculate & send every 2 seconds

// --- ESP-NOW Data Structure ---
// This MUST match the structure on your Gateway
typedef struct struct_message {
    float flow_rate;
} struct_message;

struct_message myData;

// ESP-NOW peer info
esp_now_peer_info_t peerInfo;

// --- Callback when data is sent (for debugging) ---
void OnDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  Serial.print("\r\nLast Packet Send Status:\t");
  Serial.println(status == ESP_NOW_SEND_SUCCESS ? "Delivery Success" : "Delivery Fail");
}

void setup() {
  Serial.begin(115200);
  pinMode(LOCAL_SENSOR_PIN, INPUT);
  
  // Set device as a Wi-Fi Station (required for ESP-NOW)
  WiFi.mode(WIFI_STA);
  
  // This is the MAC address for THIS remote sensor.
  // Your Gateway code must have this in its 'remote_mac_1' or 'remote_mac_2' list.
  Serial.print("This Sensor's MAC Address: ");
  Serial.println(WiFi.macAddress());

  // Init ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }

  // Register the send callback
  esp_now_register_send_cb(OnDataSent);

  // Register the Gateway as a peer
  memcpy(peerInfo.peer_addr, gateway_mac, 6);
  peerInfo.channel = 0;  
  peerInfo.encrypt = false;
  
  // Add peer
  if (esp_now_add_peer(&peerInfo) != ESP_OK){
    Serial.println("Failed to add peer");
    return;
  }
}

void loop() {
  unsigned long current_time = millis();

  // --- 1. Local Pulse Counting ---
  int adc = analogRead(LOCAL_SENSOR_PIN);
  if (adc > 110) {
    if (last_memory == 0) {
      pulse_count++;
    }
    last_memory = 1;
  } else {
    last_memory = 0;
  }

  // --- 2. Flow Calculation & Sending (every 2 seconds) ---
  if (current_time - last_calc_time >= CALC_AND_SEND_INTERVAL) {
    last_calc_time = current_time;

    // --- Calculation (from your datasheet) ---
    float interval_seconds = CALC_AND_SEND_INTERVAL / 1000.0;
    float frequency_Hz = pulse_count / interval_seconds;
    current_flow_LPM = frequency_Hz / 6.6;

    if (pulse_count == 0) {
        current_flow_LPM = 0.0;
    }
    
    Serial.printf("[LOCAL] Flow: %.2f L/min\n", current_flow_LPM);

    // --- Send Data via ESP-NOW ---
    myData.flow_rate = current_flow_LPM;
    esp_err_t result = esp_now_send(gateway_mac, (uint8_t *) &myData, sizeof(myData));
    
    if (result != ESP_OK) {
      Serial.println("Error sending the data");
    }

    // Reset pulse count for the next interval
    pulse_count = 0;
  }
}
*/