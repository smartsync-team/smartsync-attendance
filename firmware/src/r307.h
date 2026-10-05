#pragma once
#include <Arduino.h>

// Minimal driver for R307 / AS608 / R503-family optical sensors.
// Unlike most Arduino libraries it can upload AND download full templates,
// which the app needs to keep templates in the database and load only one
// course onto the sensor at a time.
namespace R307 {
constexpr uint8_t OK = 0x00;
constexpr uint8_t NO_FINGER = 0x02;
constexpr uint8_t IMAGE_FAIL = 0x03;
constexpr uint8_t NO_MATCH = 0x08;
constexpr uint8_t NOT_FOUND = 0x09;
constexpr uint8_t ENROLL_MISMATCH = 0x0A;
constexpr uint8_t BAD_PACKET = 0xFE;
constexpr uint8_t TIMEOUT = 0xFF;
}  // namespace R307

class R307Sensor {
 public:
  explicit R307Sensor(HardwareSerial& serial) : ser(serial) {}

  bool begin(int rxPin, int txPin, uint32_t baud);
  uint8_t readParams();                       // fills capacity + packetLen
  uint8_t getImage();                         // OK when a finger is on the sensor
  uint8_t image2Tz(uint8_t buffer);           // image -> features in CharBuffer 1|2
  uint8_t match(uint16_t* score);             // compare CharBuffer1 vs CharBuffer2
  uint8_t createModel();                      // merge buffers 1+2 into a template
  uint8_t storeModel(uint8_t buffer, uint16_t slot);
  uint8_t search(uint8_t buffer, uint16_t start, uint16_t count, uint16_t* slot, uint16_t* score);
  uint8_t emptyLibrary();
  uint8_t templateCount(uint16_t* count);
  uint8_t uploadTemplate(uint8_t buffer, uint8_t* out, size_t maxLen, size_t* len);
  uint8_t downloadTemplate(uint8_t buffer, const uint8_t* data, size_t len);

  uint16_t capacity = 200;
  uint16_t packetLen = 128;
  bool present = false;

 private:
  HardwareSerial& ser;
  void writePacket(uint8_t pid, const uint8_t* data, uint16_t len);
  bool readPacket(uint8_t* pid, uint8_t* data, uint16_t* len, uint16_t maxLen, uint32_t timeoutMs);
  uint8_t command(const uint8_t* cmd, uint16_t len, uint8_t* reply = nullptr, uint16_t* replyLen = nullptr,
                  uint32_t timeoutMs = 1500);
};
