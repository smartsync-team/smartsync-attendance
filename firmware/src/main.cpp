// Fingerprint attendance device firmware (ESP32 + R307/AS608).
//
// The phone app drives everything over BLE using line-delimited JSON.
// See docs/PROTOCOL.md for every command and event.
//
// Modes:
//   Idle    – waiting for commands
//   Enroll  – 3 captures of the same finger -> template sent to the app
//   Verify  – every matched finger is logged locally and sent to the app

#include <Arduino.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include <sys/time.h>

#include <vector>

#include "config.h"
#include "mbedtls/base64.h"
#include "r307.h"

HardwareSerial FingerSerial(2);
R307Sensor finger(FingerSerial);

static char deviceName[24];
static NimBLECharacteristic* evtChar = nullptr;
static volatile bool bleConnected = false;
static volatile uint16_t peerMtu = 23;
static SemaphoreHandle_t rxLock;
static std::string rxBuffer;

enum class Mode { Idle, Enroll, Verify };
static Mode mode = Mode::Idle;
static String sessionId;
static std::vector<bool> matched;  // slot -> already marked in this session
static uint8_t enrollStep = 0;
static bool waitLift = false;
static uint32_t enrollDeadline = 0;

static uint8_t tplBuf[2048];
static char b64Buf[2800];

// ---------------------------------------------------------------------------
// Feedback
// ---------------------------------------------------------------------------
static void pinOut(int pin, int level) {
  if (pin >= 0) digitalWrite(pin, level);
}

static void feedback(bool ok) {
  pinOut(ok ? LED_OK_PIN : LED_ERR_PIN, HIGH);
  if (ok) {
    pinOut(BUZZER_PIN, HIGH);
    delay(80);
    pinOut(BUZZER_PIN, LOW);
  } else {
    for (int i = 0; i < 2; i++) {
      pinOut(BUZZER_PIN, HIGH);
      delay(60);
      pinOut(BUZZER_PIN, LOW);
      delay(60);
    }
  }
  delay(150);
  pinOut(ok ? LED_OK_PIN : LED_ERR_PIN, LOW);
}

static int batteryPercent() {
  if (BATTERY_ADC_PIN < 0) return -1;
  const float v = analogReadMilliVolts(BATTERY_ADC_PIN) * BATTERY_DIVIDER / 1000.0f;
  return constrain((int)((v - 3.3f) / (4.2f - 3.3f) * 100), 0, 100);
}

// ---------------------------------------------------------------------------
// BLE output: one JSON object per line, split to fit the negotiated MTU
// ---------------------------------------------------------------------------
static void sendLine(const String& line) {
  Serial.print("-> ");
  Serial.println(line.length() > 120 ? line.substring(0, 120) + "..." : line);
  if (!bleConnected || evtChar == nullptr) return;
  const String s = line + "\n";
  const size_t chunk = peerMtu > 23 ? peerMtu - 3 : 20;
  for (size_t i = 0; i < s.length(); i += chunk) {
    const size_t n = min(chunk, s.length() - i);
    evtChar->setValue((const uint8_t*)s.c_str() + i, n);
    evtChar->notify();
    delay(8);  // notifications have no flow control; give the stack time
  }
}

static void send(JsonDocument& doc) {
  String out;
  serializeJson(doc, out);
  sendLine(out);
}

static void sendSimple(const char* evt) {
  JsonDocument d;
  d["evt"] = evt;
  send(d);
}

static void sendError(const char* msg, uint8_t code = 0) {
  JsonDocument d;
  d["evt"] = "ERROR";
  d["msg"] = msg;
  if (code) d["code"] = code;
  send(d);
}

static void sendMode() {
  JsonDocument d;
  d["evt"] = "MODE";
  d["mode"] = mode == Mode::Verify ? "verify" : (mode == Mode::Enroll ? "enroll" : "idle");
  send(d);
}

static void sendInfo() {
  uint16_t count = 0;
  if (finger.present) finger.templateCount(&count);
  JsonDocument d;
  d["evt"] = "INFO";
  d["id"] = deviceName;
  d["fw"] = FW_VERSION;
  d["cap"] = finger.capacity > 0 ? finger.capacity - 1 : 0;  // slot 0 unused
  d["count"] = count;
  d["sensor"] = finger.present;
  const int bat = batteryPercent();
  if (bat >= 0) d["bat"] = bat;
  send(d);
}

// ---------------------------------------------------------------------------
// BLE input
// ---------------------------------------------------------------------------
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, ble_gap_conn_desc* desc) override {
    bleConnected = true;
    peerMtu = server->getPeerMTU(desc->conn_handle);
    Serial.println("BLE connected");
  }
  void onDisconnect(NimBLEServer*) override {
    bleConnected = false;
    peerMtu = 23;
    Serial.println("BLE disconnected — still recording in current mode");
    NimBLEDevice::startAdvertising();
  }
  void onMTUChange(uint16_t mtu, ble_gap_conn_desc*) override { peerMtu = mtu; }
};

class CommandCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    const std::string v = c->getValue();
    xSemaphoreTake(rxLock, portMAX_DELAY);
    rxBuffer += v;
    if (rxBuffer.size() > 16384) rxBuffer.clear();  // garbage guard
    xSemaphoreGive(rxLock);
  }
};

static bool nextLine(std::string& line) {
  xSemaphoreTake(rxLock, portMAX_DELAY);
  const size_t pos = rxBuffer.find('\n');
  const bool found = pos != std::string::npos;
  if (found) {
    line = rxBuffer.substr(0, pos);
    rxBuffer.erase(0, pos + 1);
  }
  xSemaphoreGive(rxLock);
  return found;
}

// ---------------------------------------------------------------------------
// Local scan log: "session,slot,timestamp" per line
// ---------------------------------------------------------------------------
static void appendLog(uint16_t slot, time_t ts) {
  File f = LittleFS.open(LOG_PATH, FILE_APPEND);
  if (!f) return;
  f.printf("%s,%u,%ld\n", sessionId.c_str(), slot, (long)ts);
  f.close();
}

static void trimLogIfLarge() {
  File f = LittleFS.open(LOG_PATH, FILE_READ);
  const size_t size = f ? f.size() : 0;
  if (f) f.close();
  if (size > LOG_MAX_BYTES) LittleFS.remove(LOG_PATH);
}

static void replayLog(const String& session) {
  int count = 0;
  File f = LittleFS.open(LOG_PATH, FILE_READ);
  if (f) {
    while (f.available()) {
      const String line = f.readStringUntil('\n');
      const int a = line.indexOf(','), b = line.lastIndexOf(',');
      if (a < 0 || b <= a || line.substring(0, a) != session) continue;
      JsonDocument d;
      d["evt"] = "MATCH";
      d["slot"] = line.substring(a + 1, b).toInt();
      d["ts"] = line.substring(b + 1).toInt();
      d["replay"] = true;
      send(d);
      count++;
    }
    f.close();
  }
  JsonDocument d;
  d["evt"] = "SYNC_DONE";
  d["count"] = count;
  send(d);
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------
static void handleLoad(JsonDocument& doc) {
  const int slot = doc["slot"] | -1;
  const char* b64 = doc["tpl"] | "";
  if (slot < 1 || slot >= finger.capacity) return sendError("slot out of range");

  size_t len = 0;
  if (mbedtls_base64_decode(tplBuf, sizeof(tplBuf), &len, (const unsigned char*)b64, strlen(b64)) != 0 || len == 0) {
    return sendError("bad template");
  }
  uint8_t code = finger.downloadTemplate(1, tplBuf, len);
  if (code == R307::OK) code = finger.storeModel(1, slot);
  if (code != R307::OK) return sendError("store failed", code);

  JsonDocument d;
  d["evt"] = "LOAD_OK";
  d["slot"] = slot;
  send(d);
}

static void handleLine(const std::string& line) {
  JsonDocument doc;
  if (deserializeJson(doc, line)) return sendError("bad json");
  const String cmd = doc["cmd"] | "";
  Serial.println("<- " + cmd);

  if (cmd == "INFO") {
    sendInfo();
  } else if (cmd == "SET_TIME") {
    timeval tv{(time_t)(doc["ts"] | 0L), 0};
    settimeofday(&tv, nullptr);
    sendSimple("TIME_OK");
  } else if (!finger.present && cmd != "SYNC" && cmd != "IDLE") {
    sendError("fingerprint sensor not detected");
  } else if (cmd == "CLEAR") {
    mode = Mode::Idle;
    const uint8_t code = finger.emptyLibrary();
    code == R307::OK ? sendSimple("CLEAR_OK") : sendError("clear failed", code);
  } else if (cmd == "LOAD") {
    handleLoad(doc);
  } else if (cmd == "ENROLL") {
    mode = Mode::Enroll;
    enrollStep = 1;
    waitLift = false;
    enrollDeadline = millis() + ENROLL_TIMEOUT_S * 1000UL;
    JsonDocument d;
    d["evt"] = "PLACE";
    d["n"] = 1;
    send(d);
  } else if (cmd == "CANCEL" || cmd == "IDLE") {
    mode = Mode::Idle;
    sendMode();
  } else if (cmd == "VERIFY_MODE") {
    const String s = doc["session"] | "";
    if (s != sessionId) {  // new session: forget who was marked
      trimLogIfLarge();
      sessionId = s;
      matched.assign(finger.capacity + 1, false);
    }
    mode = Mode::Verify;
    waitLift = false;
    sendMode();
  } else if (cmd == "SYNC") {
    replayLog(doc["session"] | "");
  } else if (cmd == "CLEAR_LOG") {
    LittleFS.remove(LOG_PATH);
    sendSimple("LOG_CLEARED");
  } else {
    sendError("unknown command");
  }
}

// ---------------------------------------------------------------------------
// Mode loops (called repeatedly; each getImage() takes ~100–300 ms)
// ---------------------------------------------------------------------------
static void enrollFail(const char* reason) {
  mode = Mode::Idle;
  JsonDocument d;
  d["evt"] = "ENROLL_FAIL";
  d["reason"] = reason;
  send(d);
  feedback(false);
}

static void enrollTick() {
  if ((int32_t)(millis() - enrollDeadline) > 0) return enrollFail("timeout");

  const uint8_t img = finger.getImage();
  if (waitLift) {
    if (img == R307::NO_FINGER) {
      waitLift = false;
      JsonDocument d;
      d["evt"] = "PLACE";
      d["n"] = enrollStep;
      send(d);
    }
    return;
  }
  if (img != R307::OK) return;  // no finger yet

  // Captures 1 and 2 build the model; capture 3 checks it.
  const uint8_t buffer = enrollStep == 1 ? 1 : 2;
  if (finger.image2Tz(buffer) != R307::OK) {
    JsonDocument d;
    d["evt"] = "POOR_IMAGE";
    send(d);
    waitLift = true;
    feedback(false);
    return;
  }

  JsonDocument cap;
  cap["evt"] = "CAPTURE";
  cap["n"] = enrollStep;
  send(cap);
  feedback(true);
  enrollDeadline = millis() + ENROLL_TIMEOUT_S * 1000UL;

  if (enrollStep == 2 && finger.createModel() != R307::OK) return enrollFail("mismatch");

  if (enrollStep < 3) {
    enrollStep++;
    waitLift = true;
    sendSimple("LIFT");
    return;
  }

  uint16_t score = 0;
  if (finger.match(&score) != R307::OK) return enrollFail("verify");

  size_t len = 0;
  if (finger.uploadTemplate(1, tplBuf, sizeof(tplBuf), &len) != R307::OK) return enrollFail("upload");
  size_t outLen = 0;
  mbedtls_base64_encode((unsigned char*)b64Buf, sizeof(b64Buf), &outLen, tplBuf, len);
  b64Buf[outLen] = 0;

  mode = Mode::Idle;
  JsonDocument d;
  d["evt"] = "ENROLL_OK";
  d["tpl"] = (const char*)b64Buf;
  d["score"] = score;
  send(d);
}

static void verifyTick() {
  const uint8_t img = finger.getImage();
  if (waitLift) {
    if (img == R307::NO_FINGER) waitLift = false;
    return;
  }
  if (img != R307::OK) return;
  waitLift = true;  // one scan per finger placement

  uint16_t slot = 0, score = 0;
  if (finger.image2Tz(1) != R307::OK ||
      finger.search(1, 0, finger.capacity, &slot, &score) != R307::OK) {
    sendSimple("NO_MATCH");
    feedback(false);
    return;
  }

  const bool dup = slot < matched.size() && matched[slot];
  const time_t ts = time(nullptr);
  if (!dup) {
    if (slot < matched.size()) matched[slot] = true;
    appendLog(slot, ts);
  }
  JsonDocument d;
  d["evt"] = "MATCH";
  d["slot"] = slot;
  d["score"] = score;
  d["ts"] = (long)ts;
  d["dup"] = dup;
  send(d);
  feedback(true);
}

// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  for (int pin : {LED_OK_PIN, LED_ERR_PIN, BUZZER_PIN})
    if (pin >= 0) pinMode(pin, OUTPUT);

  rxLock = xSemaphoreCreateMutex();
  if (!LittleFS.begin(true)) Serial.println("LittleFS mount failed");

  if (finger.begin(FP_RX_PIN, FP_TX_PIN, FP_BAUD)) {
    Serial.printf("Sensor OK: capacity %u, packet %u bytes\n", finger.capacity, finger.packetLen);
  } else {
    Serial.println("Fingerprint sensor NOT found — check wiring (TX->16, RX->17) and power");
  }
  matched.assign(finger.capacity + 1, false);

  const uint64_t mac = ESP.getEfuseMac();
  snprintf(deviceName, sizeof(deviceName), NAME_PREFIX "%02X%02X", (uint8_t)(mac >> 32), (uint8_t)(mac >> 40));

  NimBLEDevice::init(deviceName);
  NimBLEDevice::setMTU(517);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  NimBLEService* svc = server->createService(SERVICE_UUID);
  NimBLECharacteristic* cmd = svc->createCharacteristic(CMD_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  cmd->setCallbacks(new CommandCallbacks());
  evtChar = svc->createCharacteristic(EVT_UUID, NIMBLE_PROPERTY::NOTIFY);
  svc->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);  // name goes in the scan response (128-bit UUID fills the advert)
  adv->start();

  Serial.printf("%s ready, advertising over BLE\n", deviceName);
  feedback(finger.present);
}

void loop() {
  std::string line;
  while (nextLine(line)) handleLine(line);

  switch (mode) {
    case Mode::Enroll:
      enrollTick();
      break;
    case Mode::Verify:
      verifyTick();
      break;
    default:
      delay(20);
  }
}
