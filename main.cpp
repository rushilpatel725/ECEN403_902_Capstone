
#include <WiFi.h>
#include <HTTPClient.h>
#include <time.h>
#include <esp_now.h> 

// --- Wi-Fi & Firebase ---
#define WIFI_SSID "TAMU_IoT"
#define FB_URL_PUT_SENSORS "https://iot-water-leak-default-rtdb.firebaseio.com/leak_reading.json"
#define FB_URL_GET_VALVE "https://iot-water-leak-default-rtdb.firebaseio.com/cmd/main_valve.json"
 
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
// These are accessed by both tasks, so we need to be careful.
volatile unsigned long pulse_count = 0; 
portMUX_TYPE timerMux = portMUX_INITIALIZER_UNLOCKED; // Protects the counter

// --- Globals for Local Flow Calculation ---
float current_flow_LPM = 0.0;

// --- Globals for Remote Sensors ---
float remote_flow_1 = 0.0;
float remote_flow_2 = 0.0;
unsigned long last_remote_1_time = 0;
unsigned long last_remote_2_time = 0;
const long REMOTE_TIMEOUT = 15000; 

uint8_t remote_mac_1[] = {0x80, 0xF3, 0xDA, 0x55, 0x06, 0xF0};
uint8_t remote_mac_2[] = {0x80, 0xF3, 0xDA, 0x54, 0x7A, 0x48};

// ESP-NOW Data Structure
typedef struct struct_message {
    float flow_rate;
} struct_message;
struct_message incoming_data;

// --- Globals for Valve Control ---
String lastState = "";
int active_pulse_pin = 0; 
unsigned long pulse_start_time = 0;

// --- Timers ---
unsigned long last_calc_time = 0;
unsigned long last_send_time = 0;
unsigned long last_get_time = 0; 

const long CALC_INTERVAL = 2000;  
const long SEND_INTERVAL = 3000;  
const long GET_INTERVAL = 1000;   

// --- Function Prototypes ---
void sendLeakStatus(float localFlow, float remote1Flow, float remote2Flow);
void checkFirebaseForCommand();
void startPulse(int pin);

// --- TASK HANDLE ---
TaskHandle_t Task1;

// ==========================================
//   SEPARATE CORE TASK: ANALOG SENSOR
// ==========================================
// This code runs on Core 0 independently of the Main Loop
void SensorTaskCode( void * parameter) {
  int last_memory = 0;
  
  for(;;) { // Infinite loop for this task
    int adc = analogRead(LOCAL_SENSOR_PIN);
    
    // Your original analog logic
    if (adc > 110) {
      if (last_memory == 0) {
        // Critical Section: Protect the shared variable
        portENTER_CRITICAL(&timerMux);
        pulse_count++;
        portEXIT_CRITICAL(&timerMux);
      }
      last_memory = 1;
    } else {
      last_memory = 0;
    }

    // Small delay to prevent Watchdog Timer crash (allows CPU to breathe)
    // 1ms is plenty fast for flow meters (1ms = 1000Hz max sampling)
    vTaskDelay(1 / portTICK_PERIOD_MS); 
  }
}

// --- ESP-NOW Receive Callback ---
void OnDataRecv(const uint8_t * mac, const uint8_t *incomingData, int len) {
  memcpy(&incoming_data, incomingData, sizeof(incoming_data));
  if (memcmp(mac, remote_mac_1, 6) == 0) {
    remote_flow_1 = incoming_data.flow_rate;
    last_remote_1_time = millis();
    Serial.printf("Received data from Remote 1: %.2f\n", remote_flow_1);
  } else if (memcmp(mac, remote_mac_2, 6) == 0) {
    remote_flow_2 = incoming_data.flow_rate;
    last_remote_2_time = millis();
    Serial.printf("Received data from Remote 2: %.2f\n", remote_flow_2);
  }
}

void setup() {
  Serial.begin(115200);
  
  pinMode(LOCAL_SENSOR_PIN, INPUT);
  pinMode(OPEN_PIN, OUTPUT);
  pinMode(CLOSE_PIN, OUTPUT);
  digitalWrite(OPEN_PIN, LOW);
  digitalWrite(CLOSE_PIN, LOW);

  // --- START THE SEPARATE SENSOR TASK ---
  // xTaskCreatePinnedToCore(Function, Name, StackSize, Param, Priority, Handle, CoreID)
  xTaskCreatePinnedToCore(
      SensorTaskCode,   /* Task function. */
      "SensorTask",     /* name of task. */
      10000,            /* Stack size of task */
      NULL,             /* parameter of the task */
      1,                /* priority of the task */
      &Task1,           /* Task handle to keep track of created task */
      0);               /* pin task to core 0 */                  

  // --- Wi-Fi ---
  WiFi.mode(WIFI_STA); 
  WiFi.begin(WIFI_SSID);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }
  Serial.println("\nWi-Fi connected");
  
  configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, "pool.ntp.org", "time.nist.gov");

  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }
  esp_now_register_recv_cb(OnDataRecv);
}

void loop() {
  unsigned long current_time = millis();

  // --- 1. Valve Pulse Logic ---
  if (active_pulse_pin != 0) {
    if (current_time - pulse_start_time >= PULSE_DURATION) {
      digitalWrite(active_pulse_pin, LOW); 
      Serial.printf("Pulse finished on pin %d\n", active_pulse_pin);
      active_pulse_pin = 0; 
    }
  }

  // --- 2. Local Flow Calculation ---
  if (current_time - last_calc_time >= CALC_INTERVAL) {
    last_calc_time = current_time;
    
    // Retrieve count safely
    portENTER_CRITICAL(&timerMux);
    unsigned long pulses_this_interval = pulse_count;
    pulse_count = 0; 
    portEXIT_CRITICAL(&timerMux);

    float interval_seconds = CALC_INTERVAL / 1000.0;
    float frequency_Hz = pulses_this_interval / interval_seconds;
    current_flow_LPM = frequency_Hz / 6.6;

    if (pulses_this_interval == 0) current_flow_LPM = 0.0;
    
    Serial.printf("[LOCAL] Flow: %.2f L/min\n", current_flow_LPM);
  }

  // --- 3. Remote Timeouts ---
  if (current_time - last_remote_1_time > REMOTE_TIMEOUT) remote_flow_1 = 0.0;
  if (current_time - last_remote_2_time > REMOTE_TIMEOUT) remote_flow_2 = 0.0;

  // --- 4. Send to Firebase ---
  if (current_time - last_send_time >= SEND_INTERVAL) {
    last_send_time = current_time;
    sendLeakStatus(current_flow_LPM, remote_flow_1, remote_flow_2);
  }

  // --- 5. Get Commands ---
  if (current_time - last_get_time >= GET_INTERVAL) {
    last_get_time = current_time;
    checkFirebaseForCommand();
  }
}

// --- Non-Blocking Pulse Starter ---
void startPulse(int pin) {
  if (active_pulse_pin != 0) return;
  Serial.printf("Pulsing pin %d...\n", pin);
  active_pulse_pin = pin; 
  pulse_start_time = millis(); 
  digitalWrite(pin, HIGH); 
}

// --- Check Firebase ---
void checkFirebaseForCommand() {
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

// --- Send Data ---
void sendLeakStatus(float localFlow, float remote1Flow, float remote2Flow) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(FB_URL_PUT_SENSORS); 
    http.addHeader("Content-Type", "application/json");

    struct tm timeinfo;
    if (!getLocalTime(&timeinfo)) {
        http.end();
        return;
    }
    char timeString[30];
    strftime(timeString, sizeof(timeString), "%Y-%m-%d %H:%M:%S", &timeinfo);

    String payload = "{";
    payload += "\"local_sensor\": " + String(localFlow, 2) + ",";
    payload += "\"remote_sensor_1\": " + String(remote1Flow, 2) + ",";
    payload += "\"remote_sensor_2\": " + String(remote2Flow, 2) + ",";
    payload += "\"time\": \"" + String(timeString) + "\"";
    payload += "}";

    http.PUT(payload); 
    http.end();
  }
}