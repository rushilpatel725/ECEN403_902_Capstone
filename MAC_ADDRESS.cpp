/*
#include <WiFi.h>
#include <esp_wifi.h>

void setup() {
  Serial.begin(115200);

  // Set Wi-Fi to Station mode (required for reading MAC)
  WiFi.mode(WIFI_STA);

  // Get MAC address
  uint8_t mac[6];
  if (esp_wifi_get_mac(WIFI_IF_STA, mac) == ESP_OK) {
    Serial.printf("ESP32 MAC Address: %02X:%02X:%02X:%02X:%02X:%02X\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  } else {
    Serial.println("Failed to read MAC address");
  }
}

void loop() {
  // Nothing here
}
*/