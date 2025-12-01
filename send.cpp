/*
#include <esp_now.h>
#include <WiFi.h>

uint8_t gateway_mac[] = {0x8C, 0x4F, 0x00, 0x30, 0x53, 0x1C};

// --- Sensor Pin ---
// MUST use an ADC1 pin (GPIO 32, 33, 34, 35, 36, 39). 
// GPIO 33 is perfect.
#define LOCAL_SENSOR_PIN 33 

// --- Shared Globals (Protected) ---
// Accessed by both the Sensor Task and the Main Loop
volatile unsigned long pulse_count = 0; 
portMUX_TYPE timerMux = portMUX_INITIALIZER_UNLOCKED; 

// --- Globals for Local Sensor ---
float current_flow_LPM = 0.0; 

// --- Timer ---
unsigned long last_calc_time = 0;
const long CALC_AND_SEND_INTERVAL = 2000; // Calculate & send every 2 seconds

// --- ESP-NOW Data Structure ---
typedef struct struct_message {
    float flow_rate;
} struct_message;

struct_message myData;

esp_now_peer_info_t peerInfo;

// --- TASK HANDLE ---
TaskHandle_t SensorTask;

// ==========================================
//   SEPARATE CORE TASK: ANALOG SENSOR
// ==========================================
// This code runs on Core 0. It does nothing but watch the sensor.
void SensorTaskCode( void * parameter) {
  int last_memory = 0;
  
  for(;;) { // Infinite loop
    int adc = analogRead(LOCAL_SENSOR_PIN);
    
    // Your threshold logic (ADC > 110)
    if (adc > 110) {
      if (last_memory == 0) {
        // Critical Section: Protect the counter while modifying it
        portENTER_CRITICAL(&timerMux);
        pulse_count++;
        portEXIT_CRITICAL(&timerMux);
      }
      last_memory = 1;
    } else {
      last_memory = 0;
    }

    // A tiny delay is required to prevent the Watchdog Timer from crashing the ESP
    // 1ms is very fast (1000Hz sampling), usually plenty for flow meters.
    vTaskDelay(1 / portTICK_PERIOD_MS); 
  }
}

// --- Callback when data is sent ---
void OnDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  // Optional: Debugging
  // Serial.print("\r\nLast Packet Send Status:\t");
  // Serial.println(status == ESP_NOW_SEND_SUCCESS ? "Delivery Success" : "Delivery Fail");
}

void setup() {
  Serial.begin(115200);

  // --- 1. Setup Sensor Pin ---
  pinMode(LOCAL_SENSOR_PIN, INPUT);
  
  // --- 2. Create the Analog Sensor Task ---
  // This launches the "SensorTaskCode" function on Core 0
  xTaskCreatePinnedToCore(
      SensorTaskCode,   
      "SensorTask",     
      10000,            
      NULL,             
      1,                
      &SensorTask,      
      0);               

  // --- 3. Setup ESP-NOW ---
  WiFi.mode(WIFI_STA);

  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }

  esp_now_register_send_cb(OnDataSent);

  memcpy(peerInfo.peer_addr, gateway_mac, 6);
  peerInfo.channel = 0;  
  peerInfo.encrypt = false;
  
  if (esp_now_add_peer(&peerInfo) != ESP_OK){
    Serial.println("Failed to add peer");
    return;
  }
}

void loop() {
  // This loop runs on Core 1
  unsigned long current_time = millis();

  // --- Flow Calculation & Sending (every 2 seconds) ---
  if (current_time - last_calc_time >= CALC_AND_SEND_INTERVAL) {
    last_calc_time = current_time;

    // --- CRITICAL SECTION START ---
    // Pause the sensor task access briefly to safely read/reset the number
    portENTER_CRITICAL(&timerMux);
    unsigned long pulses_this_interval = pulse_count; 
    pulse_count = 0; 
    portEXIT_CRITICAL(&timerMux);
    // --- CRITICAL SECTION END ---

    // --- Calculation ---
    float interval_seconds = CALC_AND_SEND_INTERVAL / 1000.0;
    float frequency_Hz = pulses_this_interval / interval_seconds;
    current_flow_LPM = frequency_Hz / 6.6; // Your calibration factor

    if (pulses_this_interval == 0) {
        current_flow_LPM = 0.0;
    }
    
    Serial.printf("[LOCAL] Flow: %.2f L/min | Pulses: %lu\n", current_flow_LPM, pulses_this_interval);

    // --- Send Data via ESP-NOW ---
    myData.flow_rate = current_flow_LPM;
    esp_err_t result = esp_now_send(gateway_mac, (uint8_t *) &myData, sizeof(myData));
    
    if (result != ESP_OK) {
      Serial.println("Error sending the data");
    }
  }
}
*/