
#include <esp_now.h>
#include <WiFi.h>


#define LOCAL_SENSOR_PIN 33
int count = 0;
int memory = 0;
float local_flow = 0.0;
unsigned long lastSendTime = 0;
const unsigned long sendInterval = 2000; // 2 sec

//MAC address
uint8_t receiverMAC[] = {0x80, 0xF3, 0xDA, 0x54, 0x66, 0x64};

//Struct for data
typedef struct struct_message {
  int id;
  float flow_Lmin;
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
  
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }

  esp_now_register_send_cb(OnDataSent);

  memcpy(peerInfo.peer_addr, receiverMAC, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;

  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("Failed to add peer");
    return;
  }

  sendingData.id = 2;
}


void loop() {
  // Example: update flow reading (replace with real reading)
  sendingData.flow_Lmin = 1.0;
  esp_now_send(receiverMAC, (uint8_t *) &sendingData, sizeof(sendingData));
  delay(2000);
}

