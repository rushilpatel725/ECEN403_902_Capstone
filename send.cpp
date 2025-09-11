#include <esp_now.h>
#include <WiFi.h>

//MAC address
uint8_t receiverMAC[] = {0x3C, 0x8A, 0x1F, 0x77, 0x91, 0xA0};

//Struct for data
typedef struct struct_message {
  int id;
  float value;
} struct_message;

struct_message sendingData;

//stores information about peer
esp_now_peer_info_t peerInfo;

//Prints if message sends successfully or not
void OnDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  Serial.print("Delivery Status: ");
  Serial.println(status == ESP_NOW_SEND_SUCCESS ? "Success" : "Fail");
}

void setup() {
  Serial.begin(115200);

  WiFi.mode(WIFI_STA);
  
  //initialize ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }

  //registers callback function 
  esp_now_register_send_cb(OnDataSent);

  // Register other board
  memcpy(peerInfo.peer_addr, receiverMAC, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;

  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("Failed to add peer");
    return;
  }
}

void loop() {
  //Replace with sensor data
  sendingData.id = 1;
  sendingData.value = random(0, 100) / 1.0;

  //Send the message
  esp_err_t result = esp_now_send(receiverMAC, (uint8_t *) &sendingData, sizeof(sendingData));

  if (result == ESP_OK) {
    Serial.println("Sent with success");
  } else {
    Serial.println("Error sending data");
  }
  delay(10000);
}
