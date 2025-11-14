#include <WiFi.h>
#include <HTTPClient.h>
#include <time.h>
#include <esp_now.h> 

// --- Wi-Fi & Firebase ---
#define WIFI_SSID "TAMU_IoT"
// URL for PUT-ing sensor data
#define FB_URL_PUT_SENSORS "https://iot-water-leak-default-rtdb.firebaseio.com/leak_reading.json"
// URL for GET-ing valve commands
#define FB_URL_GET_VALVE "https://iot-water-leak-default-rtdb.firebaseio.com/cmd/main_valve.json"
 
// --- Time ---
#define GMT_OFFSET_SEC     -21600
#define DAYLIGHT_OFFSET_SEC 3600

// --- Local Sensor Pin ---
#define LOCAL_SENSOR_PIN 33

// --- Valve Control Pins ---
#define OPEN_PIN 21
#define CLOSE_PIN 5
#define PULSE_DURATION 2000 // 2-second pulse

// --- Globals for Local Sensor ---
float current_flow_LPM = 0.0;
int pulse_count = 0;         
int last_memory = 0;         

// --- Globals for Remote Sensors ---
float remote_flow_1 = 0.0;
float remote_flow_2 = 0.0;
unsigned long last_remote_1_time = 0;
unsigned long last_remote_2_time = 0;
const long REMOTE_TIMEOUT = 15000; // 15 seconds

// MAC Addresses of remote sensors
uint8_t remote_mac_1[] = {0x80, 0xF3, 0xDA, 0x55, 0x06, 0xF0};
uint8_t remote_mac_2[] = {0x80, 0xF3, 0xDA, 0x54, 0x7A, 0x48};

// ESP-NOW Data Structure
typedef struct struct_message {
    float flow_rate;
} struct_message;
struct_message incoming_data;

// --- Globals for Valve Control ---
String lastState = "";
int active_pulse_pin = 0; // 0 = no pulse, otherwise stores the pin being pulsed
unsigned long pulse_start_time = 0;

// --- Timers ---
unsigned long last_calc_time = 0;
unsigned long last_send_time = 0;
unsigned long last_get_time = 0; // Timer for valve GET requests

const long CALC_INTERVAL = 2000;  // Calculate local flow every 2 seconds
const long SEND_INTERVAL = 3000;  // PUT data to Firebase every 3 seconds
const long GET_INTERVAL = 1000;   // GET valve command from Firebase every 1 second

// --- Function Prototypes ---
void sendLeakStatus(float localFlow, float remote1Flow, float remote2Flow);
void checkFirebaseForCommand();
void startPulse(int pin);

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
  
  // --- Initialize Pins ---
  pinMode(LOCAL_SENSOR_PIN, INPUT);
  pinMode(OPEN_PIN, OUTPUT);
  pinMode(CLOSE_PIN, OUTPUT);
  digitalWrite(OPEN_PIN, LOW);
  digitalWrite(CLOSE_PIN, LOW);
  
  // --- Wi-Fi ---
  WiFi.mode(WIFI_STA); 
  WiFi.begin(WIFI_SSID);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }
  Serial.println("\nWi-Fi connected");
  Serial.print("Gateway MAC Address: ");
  Serial.println(WiFi.macAddress());

  // --- Time Sync ---
  configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, "pool.ntp.org", "time.nist.gov");

  // --- ESP-NOW Init ---
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }
  esp_now_register_recv_cb(OnDataRecv);
}

void loop() {
  unsigned long current_time = millis();

  // --- 1. Handle Non-Blocking Valve Pulse ---
  // Checks if a pulse is active and if it's time to end it
  if (active_pulse_pin != 0) {
    if (current_time - pulse_start_time >= PULSE_DURATION) {
      digitalWrite(active_pulse_pin, LOW); // Turn off the pin
      Serial.printf("Pulse finished on pin %d\n", active_pulse_pin);
      active_pulse_pin = 0; // Clear the flag
    }
  }

  // --- 2. Local Pulse Counting ---
  int adc = analogRead(LOCAL_SENSOR_PIN);
  if (adc > 110) {
    if (last_memory == 0) {
      pulse_count++;
    }
    last_memory = 1;
  } else {
    last_memory = 0;
  }

  // --- 3. Local Flow Calculation (every CALC_INTERVAL) ---
  if (current_time - last_calc_time >= CALC_INTERVAL) {
    last_calc_time = current_time;
    
    float interval_seconds = CALC_INTERVAL / 1000.0;
    float frequency_Hz = pulse_count / interval_seconds;
    current_flow_LPM = frequency_Hz / 6.6;

    if (pulse_count == 0) {
        current_flow_LPM = 0.0;
    }
    
    Serial.printf("[LOCAL] Flow: %.2f L/min\n", current_flow_LPM);
    pulse_count = 0; 
  }

  // --- 4. Check for Remote Sensor Timeouts ---
  if (current_time - last_remote_1_time > REMOTE_TIMEOUT) {
    remote_flow_1 = 0.0;
  }
  if (current_time - last_remote_2_time > REMOTE_TIMEOUT) {
    remote_flow_2 = 0.0;
  }

  // --- 5. Data Sending to Firebase (every SEND_INTERVAL) ---
  if (current_time - last_send_time >= SEND_INTERVAL) {
    last_send_time = current_time;
    sendLeakStatus(current_flow_LPM, remote_flow_1, remote_flow_2);
  }

  // --- 6. Valve Command Check (every GET_INTERVAL) ---
  if (current_time - last_get_time >= GET_INTERVAL) {
    last_get_time = current_time;
    checkFirebaseForCommand();
  }
}

// --- Non-Blocking Pulse Starter ---
void startPulse(int pin) {
  if (active_pulse_pin != 0) {
    // A pulse is already in progress, ignore this new request
    Serial.println("Warning: Another pulse is active. Ignoring new request.");
    return;
  }
  
  Serial.printf("Pulsing pin %d...\n", pin);
  active_pulse_pin = pin; // Set the pin as active
  pulse_start_time = millis(); // Record the start time
  digitalWrite(pin, HIGH); // Turn the pin ON
}

// --- Check Firebase for Valve Command ---
void checkFirebaseForCommand() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(FB_URL_GET_VALVE);
    int httpCode = http.GET();

    if (httpCode == 200) {
      String payload = http.getString();
      payload.trim();
      payload.replace("\"", "");

      Serial.print("Firebase valve command: ");
      Serial.println(payload);

      // Only act if the state is new
      if (payload != lastState) {
        lastState = payload;
        if (payload.equalsIgnoreCase("OPEN")) {
          startPulse(OPEN_PIN);
        } else if (payload.equalsIgnoreCase("CLOSE")) {
          startPulse(CLOSE_PIN);
        } else {
          Serial.println("Unknown command received");
        }
      }
    } else {
      Serial.print("HTTP GET for valve failed, code: ");
      Serial.println(httpCode);
    }
    http.end();
  } else {
    Serial.println("WiFi disconnected, cannot check for command!");
  }
}

// --- Send Sensor Data to Firebase ---
void sendLeakStatus(float localFlow, float remote1Flow, float remote2Flow) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(FB_URL_PUT_SENSORS); 
    http.addHeader("Content-Type", "application/json");

    struct tm timeinfo;
    if (!getLocalTime(&timeinfo)) {
        Serial.println("Failed to obtain time");
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

    Serial.println("Uploading Sensor Data: " + payload);
    
    int responseCode = http.PUT(payload); 
    
    if (responseCode <= 0) {
      Serial.printf("HTTP PUT for sensors failed, code: %d\n", responseCode);
    }
    
    http.end();
  } else {
    Serial.println("WiFi disconnected, cannot send sensor data!");
  }
}