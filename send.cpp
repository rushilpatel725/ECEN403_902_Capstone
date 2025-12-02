/*
#include <WiFi.h>
#include <HTTPClient.h>
#include <time.h>

#define WIFI_SSID "TAMU_IoT"

// --- Firebase Paths ---
// CHANGED: This URL now points to "remote_sensor_2"
#define FB_URL_PUT_REMOTE "https://iot-water-leak-default-rtdb.firebaseio.com/leak_reading/remote_sensor_2.json"

// --- Sensor Pin (ADC1) ---
#define LOCAL_SENSOR_PIN 33 

// --- Shared Globals ---
volatile unsigned long pulse_count = 0; 
portMUX_TYPE timerMux = portMUX_INITIALIZER_UNLOCKED; 

// --- Globals ---
float current_flow_LPM = 0.0; 
unsigned long last_send_time = 0;
const long SEND_INTERVAL = 3000; // Send to cloud every 3 seconds

// --- Task Handle ---
TaskHandle_t SensorTask;

// ==========================================
//   CORE 0 TASK: ANALOG SENSOR
// ==========================================
void SensorTaskCode( void * parameter) {
  int last_memory = 0;
  for(;;) {
    int adc = analogRead(LOCAL_SENSOR_PIN);
    if (adc > 110) {
      if (last_memory == 0) {
        portENTER_CRITICAL(&timerMux);
        pulse_count++;
        portEXIT_CRITICAL(&timerMux);
      }
      last_memory = 1;
    } else {
      last_memory = 0;
    }
    vTaskDelay(1 / portTICK_PERIOD_MS); 
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(LOCAL_SENSOR_PIN, INPUT);

  // --- Start Sensor Task ---
  xTaskCreatePinnedToCore(SensorTaskCode, "SensorTask", 10000, NULL, 1, &SensorTask, 0);               

  // --- Wi-Fi Connection ---
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID); 
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }
  Serial.println("\nWi-Fi Connected!");
}

void loop() {
  unsigned long current_time = millis();

  if (current_time - last_send_time >= SEND_INTERVAL) {
    last_send_time = current_time;

    // 1. Safe Read & Reset
    portENTER_CRITICAL(&timerMux);
    unsigned long pulses = pulse_count; 
    pulse_count = 0; 
    portEXIT_CRITICAL(&timerMux);

    // 2. Calculate Flow
    // Interval is SEND_INTERVAL (3000ms = 3.0s)
    float interval_seconds = SEND_INTERVAL / 1000.0;
    float frequency_Hz = pulses / interval_seconds;
    current_flow_LPM = frequency_Hz / 6.6; 
    if (pulses == 0) current_flow_LPM = 0.0;
    
    Serial.printf("[REMOTE 2] Flow: %.2f L/min | Uploading...\n", current_flow_LPM);

    // 3. Upload DIRECTLY to Firebase
    if (WiFi.status() == WL_CONNECTED) {
      HTTPClient http;
      http.begin(FB_URL_PUT_REMOTE);
      http.addHeader("Content-Type", "application/json");
      
      // We send JUST the number. Firebase treats this as updating that specific field.
      int httpCode = http.PUT(String(current_flow_LPM, 2));
      
      if (httpCode > 0) {
        Serial.println("Firebase Update Success");
      } else {
        Serial.printf("Firebase Error: %d\n", httpCode);
      }
      http.end();
    }
  }
}
  */