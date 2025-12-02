
#include <WiFi.h>
#include <HTTPClient.h>
#include <time.h>

// --- Wi-Fi & Firebase ---
#define WIFI_SSID "TAMU_IoT"

// We split the updates into specific fields so we don't overwrite the Remote Sensor's data
#define FB_URL_PUT_LOCAL "https://iot-water-leak-default-rtdb.firebaseio.com/leak_reading/local_sensor.json"
#define FB_URL_PUT_TIME  "https://iot-water-leak-default-rtdb.firebaseio.com/leak_reading/time.json"
#define FB_URL_GET_VALVE "https://iot-water-leak-default-rtdb.firebaseio.com/cmd/main_valve.json"
#define FB_URL_GET_HEARTBEAT "https://iot-water-leak-default-rtdb.firebaseio.com/appHeartbeat/counter.json"
 
// --- Time ---
#define GMT_OFFSET_SEC     -21600
#define DAYLIGHT_OFFSET_SEC 3600

// --- Local Sensor Pin ---
#define LOCAL_SENSOR_PIN 33 

// --- Valve Control Pins ---
#define OPEN_PIN 21
#define CLOSE_PIN 5
#define PULSE_DURATION 2000 

// --- Shared Globals (Protected) ---
volatile unsigned long pulse_count = 0; 
portMUX_TYPE timerMux = portMUX_INITIALIZER_UNLOCKED; 

// --- Globals ---
float current_flow_LPM = 0.0;
String lastState = "";
int active_pulse_pin = 0; 
unsigned long pulse_start_time = 0;

// --- Timers ---
unsigned long last_send_time = 0;
unsigned long last_get_time = 0; 

const long SEND_INTERVAL = 3000;  
const long GET_INTERVAL = 1000; // Can be fast now because ESP-NOW isn't blocking!  

TaskHandle_t Task1;

// --- Function Prototypes ---
void sendLocalData(float localFlow);
void checkFirebaseForCommand();
void startPulse(int pin);

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
  pinMode(OPEN_PIN, OUTPUT);
  pinMode(CLOSE_PIN, OUTPUT);
  digitalWrite(OPEN_PIN, LOW);
  digitalWrite(CLOSE_PIN, LOW);

  xTaskCreatePinnedToCore(SensorTaskCode, "SensorTask", 10000, NULL, 1, &Task1, 0);               

  WiFi.mode(WIFI_STA); 
  WiFi.begin(WIFI_SSID);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }
  Serial.println("\nWi-Fi connected");
  
  configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, "pool.ntp.org", "time.nist.gov");
}

void loop() {
  unsigned long current_time = millis();

  // 1. Valve Pulse Logic
  if (active_pulse_pin != 0) {
    if (current_time - pulse_start_time >= PULSE_DURATION) {
      digitalWrite(active_pulse_pin, LOW); 
      Serial.printf("Pulse finished on pin %d\n", active_pulse_pin);
      active_pulse_pin = 0; 
    }
  }

  // SAFETY GUARD
  if (active_pulse_pin != 0) return;

  // 2. Calculate & Send (Every 3 seconds)
  if (current_time - last_send_time >= SEND_INTERVAL) {
    last_send_time = current_time;

    // Safe Read
    portENTER_CRITICAL(&timerMux);
    unsigned long pulses = pulse_count;
    pulse_count = 0; 
    portEXIT_CRITICAL(&timerMux);

    // Calc
    float interval = SEND_INTERVAL / 1000.0;
    float freq = pulses / interval;
    current_flow_LPM = freq / 6.6;
    if (pulses == 0) current_flow_LPM = 0.0;

    Serial.printf("[LOCAL] Flow: %.2f L/min\n", current_flow_LPM);
    sendLocalData(current_flow_LPM);
  }

  // 3. Get Commands (Every 1 second)
  if (current_time - last_get_time >= GET_INTERVAL) {
    last_get_time = current_time;
    checkFirebaseForCommand();
  }
}

void startPulse(int pin) {
  if (active_pulse_pin != 0) return;
  Serial.printf("Pulsing pin %d...\n", pin);
  active_pulse_pin = pin; 
  pulse_start_time = millis(); 
  digitalWrite(pin, HIGH); 
}

void checkFirebaseForCommand() {
  if (active_pulse_pin != 0) return;

  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(FB_URL_GET_VALVE);
    int httpCode = http.GET();
    if (httpCode == 200) {
      String payload = http.getString();
      payload.trim();
      payload.replace("\"", "");
      if (payload != lastState) {
        lastState = payload;
        if (payload.equalsIgnoreCase("OPEN")) startPulse(OPEN_PIN);
        else if (payload.equalsIgnoreCase("CLOSE")) startPulse(CLOSE_PIN);
      }
    }
    http.end();
  }
}

void sendLocalData(float localFlow) {
  if (active_pulse_pin != 0) return;

  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    
    // 1. Update Local Sensor Field
    http.begin(FB_URL_PUT_LOCAL); 
    http.addHeader("Content-Type", "application/json");
    http.PUT(String(localFlow, 2)); 
    http.end();

    // 2. Update Timestamp (Optional, but good for app status)
    struct tm timeinfo;
    if (getLocalTime(&timeinfo)) {
        char timeString[30];
        strftime(timeString, sizeof(timeString), "%Y-%m-%d %H:%M:%S", &timeinfo);
        http.begin(FB_URL_PUT_TIME);
        http.addHeader("Content-Type", "application/json");
        // We must wrap the string in quotes for valid JSON
        http.PUT("\"" + String(timeString) + "\""); 
        http.end();
    }
  }
}
