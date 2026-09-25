// ESP32 Potentiometer Controller (GPIO 4)
const int potPin = 4;

const float MIN_FREQ = 100.0;
const float MAX_FREQ = 1000.0;

// Smoothing factor (0.05 to 1.0) - reduces analog jitter
const float SMOOTHING = 0.1;
float smoothed_freq = 440.0;

void setup() {
  Serial.begin(115200);
  analogReadResolution(12); // Ensure full 12-bit range (0 - 4095)
  delay(1000);
}

void loop() {
  int raw = analogRead(potPin);
  
  // Inverted: 4095 - raw flips the direction (0 yields 1000.0, 4095 yields 100.0)
  float target_freq = MIN_FREQ + ((float)(4095 - raw) / 4095.0) * (MAX_FREQ - MIN_FREQ);
  
  // Apply exponential smoothing
  smoothed_freq = (smoothed_freq * (1.0 - SMOOTHING)) + (target_freq * SMOOTHING);
  
  // Send frequency to Odin application over Serial
  Serial.println(smoothed_freq, 1);
  
  delay(16); // ~60 Hz update rate
}
