#include <esp_now.h>
#include <WiFi.h>

typedef struct struct_message{
    int id;
    float value;
}struct_message;

struct_message receivedData;

//For holding readings from each board
struct_message board1;

//array for all boards
struct_message boardsStruct[1] = {board1};

//callback function when data is received
void OnDataRecv(const uint8_t * mac_addr, const uint8_t *incomingData, int len) {
    //Gets MAC Address of board
    char macStr[18];
    Serial.print("Packet received from: ");
    snprintf(macStr, sizeof(macStr), "%02x:%02x:%02x:%02x:%02x:%02x", 
        mac_addr[0], mac_addr[1], mac_addr[2], mac_addr[3], mac_addr[4], mac_addr[5]);
    Serial.println(macStr);
    
    //Copy the content of incomingData into receivedData variable
    memcpy(&receivedData, incomingData, sizeof(receivedData));
    Serial.printf("Board ID %u: %u bytes\n", receivedData, len);

    //assign values received to corresponding boards in array
    boardsStruct[receivedData.id-1].value = receivedData.value;
    Serial.printf("value: %d \n", boardsStruct[receivedData.id-1]);
    Serial.println();
}

void setup(){
    Serial.begin(115200);
    WiFi.mode(WIFI_STA);

    if (esp_now_init() != ESP_OK){
        Serial.println("Error initializing ESP-Now");
        return;
    }

    esp_now_register_recv_cb(esp_now_recv_cb_t(OnDataRecv));
}

void loop(){
    float board1Value = boardsStruct[0].value;
    delay(10000);
}