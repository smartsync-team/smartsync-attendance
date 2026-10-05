#pragma once

#define FW_VERSION "1.0.0"

// ---- Fingerprint sensor (R307 / AS608 / R503) on UART2 ----
// Sensor TX (green/yellow) -> ESP32 GPIO16, sensor RX (white) -> ESP32 GPIO17
#define FP_RX_PIN 16
#define FP_TX_PIN 17
#define FP_BAUD 57600

// ---- Feedback (set to -1 if not fitted) ----
#define LED_OK_PIN 25     // green LED
#define LED_ERR_PIN 26    // red LED
#define BUZZER_PIN 27     // active buzzer

// ---- Battery (set to -1 if not measured) ----
// Battery+ -> 100k -> GPIO34 -> 100k -> GND  (divider ratio 2)
#define BATTERY_ADC_PIN -1
#define BATTERY_DIVIDER 2.0f

// ---- BLE — must match mobile/lib/services/device_service.dart ----
#define SERVICE_UUID "a7e1f000-5b2c-4c8a-9d1e-0f1a2b3c4d5e"
#define CMD_UUID     "a7e1f001-5b2c-4c8a-9d1e-0f1a2b3c4d5e"   // app -> device (write)
#define EVT_UUID     "a7e1f002-5b2c-4c8a-9d1e-0f1a2b3c4d5e"   // device -> app (notify)

// Device advertises as "FP-Scanner-XXXX" (last bytes of the chip MAC),
// so the same firmware can be flashed to every device.
#define NAME_PREFIX "FP-Scanner-"

// Seconds to wait for a finger during enrollment before giving up.
#define ENROLL_TIMEOUT_S 60

// Local scan log (survives power loss). Trimmed when it grows past this.
#define LOG_PATH "/scans.log"
#define LOG_MAX_BYTES (256 * 1024)
