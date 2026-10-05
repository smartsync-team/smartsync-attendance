#include "r307.h"

// Packet: EF01 | addr(4)=FFFFFFFF | pid(1) | len(2) = payload+2 | payload | checksum(2)
// checksum = 16-bit sum of pid, len bytes and payload.
static constexpr uint8_t PID_COMMAND = 0x01;
static constexpr uint8_t PID_DATA = 0x02;
static constexpr uint8_t PID_ACK = 0x07;
static constexpr uint8_t PID_END = 0x08;

bool R307Sensor::begin(int rxPin, int txPin, uint32_t baud) {
  ser.begin(baud, SERIAL_8N1, rxPin, txPin);
  delay(300);  // sensor boot time
  const uint8_t verify[] = {0x13, 0, 0, 0, 0};  // VfyPwd, default password 0
  present = command(verify, sizeof(verify)) == R307::OK;
  if (present) readParams();
  return present;
}

void R307Sensor::writePacket(uint8_t pid, const uint8_t* data, uint16_t len) {
  const uint16_t pktLen = len + 2;
  const uint8_t header[9] = {0xEF, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, pid, (uint8_t)(pktLen >> 8), (uint8_t)pktLen};
  uint16_t sum = pid + (pktLen >> 8) + (pktLen & 0xFF);
  for (uint16_t i = 0; i < len; i++) sum += data[i];
  ser.write(header, sizeof(header));
  ser.write(data, len);
  ser.write((uint8_t)(sum >> 8));
  ser.write((uint8_t)sum);
}

bool R307Sensor::readPacket(uint8_t* pid, uint8_t* data, uint16_t* len, uint16_t maxLen, uint32_t timeoutMs) {
  const uint32_t start = millis();
  auto readByte = [&](uint8_t& b) -> bool {
    while (!ser.available()) {
      if (millis() - start > timeoutMs) return false;
      delay(1);
    }
    b = ser.read();
    return true;
  };

  uint8_t b = 0, prev = 0;
  while (true) {  // sync on header EF 01
    if (!readByte(b)) return false;
    if (prev == 0xEF && b == 0x01) break;
    prev = b;
  }
  uint8_t h[7];  // addr(4) pid len(2)
  for (auto& x : h)
    if (!readByte(x)) return false;

  *pid = h[4];
  const uint16_t pktLen = (h[5] << 8) | h[6];
  if (pktLen < 2 || pktLen - 2 > maxLen) return false;

  uint16_t sum = h[4] + h[5] + h[6];
  for (uint16_t i = 0; i < pktLen - 2; i++) {
    if (!readByte(data[i])) return false;
    sum += data[i];
  }
  uint8_t c1, c2;
  if (!readByte(c1) || !readByte(c2)) return false;
  *len = pktLen - 2;
  return (uint16_t)((c1 << 8) | c2) == sum;
}

uint8_t R307Sensor::command(const uint8_t* cmd, uint16_t len, uint8_t* reply, uint16_t* replyLen, uint32_t timeoutMs) {
  while (ser.available()) ser.read();  // drop stale bytes
  writePacket(PID_COMMAND, cmd, len);
  uint8_t pid;
  uint8_t buf[64];
  uint16_t n;
  if (!readPacket(&pid, buf, &n, sizeof(buf), timeoutMs)) return R307::TIMEOUT;
  if (pid != PID_ACK || n < 1) return R307::BAD_PACKET;
  if (reply && replyLen) {
    memcpy(reply, buf + 1, n - 1);
    *replyLen = n - 1;
  }
  return buf[0];
}

uint8_t R307Sensor::readParams() {
  const uint8_t cmd[] = {0x0F};
  uint8_t r[32];
  uint16_t n = 0;
  const uint8_t code = command(cmd, sizeof(cmd), r, &n);
  if (code == R307::OK && n >= 16) {
    capacity = (r[4] << 8) | r[5];
    packetLen = 32 << (r[13] & 0x03);
  }
  return code;
}

uint8_t R307Sensor::getImage() {
  const uint8_t cmd[] = {0x01};
  return command(cmd, sizeof(cmd));
}

uint8_t R307Sensor::image2Tz(uint8_t buffer) {
  const uint8_t cmd[] = {0x02, buffer};
  return command(cmd, sizeof(cmd));
}

uint8_t R307Sensor::match(uint16_t* score) {
  const uint8_t cmd[] = {0x03};
  uint8_t r[8];
  uint16_t n = 0;
  const uint8_t code = command(cmd, sizeof(cmd), r, &n);
  if (score) *score = n >= 2 ? (r[0] << 8) | r[1] : 0;
  return code;
}

uint8_t R307Sensor::createModel() {
  const uint8_t cmd[] = {0x05};
  return command(cmd, sizeof(cmd));
}

uint8_t R307Sensor::storeModel(uint8_t buffer, uint16_t slot) {
  const uint8_t cmd[] = {0x06, buffer, (uint8_t)(slot >> 8), (uint8_t)slot};
  return command(cmd, sizeof(cmd));
}

uint8_t R307Sensor::search(uint8_t buffer, uint16_t start, uint16_t count, uint16_t* slot, uint16_t* score) {
  const uint8_t cmd[] = {0x04, buffer, (uint8_t)(start >> 8), (uint8_t)start, (uint8_t)(count >> 8), (uint8_t)count};
  uint8_t r[8];
  uint16_t n = 0;
  const uint8_t code = command(cmd, sizeof(cmd), r, &n, 3000);
  if (code == R307::OK && n >= 4) {
    *slot = (r[0] << 8) | r[1];
    *score = (r[2] << 8) | r[3];
  }
  return code;
}

uint8_t R307Sensor::emptyLibrary() {
  const uint8_t cmd[] = {0x0D};
  return command(cmd, sizeof(cmd), nullptr, nullptr, 5000);
}

uint8_t R307Sensor::templateCount(uint16_t* count) {
  const uint8_t cmd[] = {0x1D};
  uint8_t r[8];
  uint16_t n = 0;
  const uint8_t code = command(cmd, sizeof(cmd), r, &n);
  *count = (code == R307::OK && n >= 2) ? (r[0] << 8) | r[1] : 0;
  return code;
}

uint8_t R307Sensor::uploadTemplate(uint8_t buffer, uint8_t* out, size_t maxLen, size_t* len) {
  const uint8_t cmd[] = {0x08, buffer};  // UpChar
  const uint8_t code = command(cmd, sizeof(cmd));
  if (code != R307::OK) return code;

  *len = 0;
  uint8_t chunk[260];
  while (true) {
    uint8_t pid;
    uint16_t n;
    if (!readPacket(&pid, chunk, &n, sizeof(chunk), 2000)) return R307::TIMEOUT;
    if (pid != PID_DATA && pid != PID_END) return R307::BAD_PACKET;
    if (*len + n > maxLen) return R307::BAD_PACKET;
    memcpy(out + *len, chunk, n);
    *len += n;
    if (pid == PID_END) return R307::OK;
  }
}

uint8_t R307Sensor::downloadTemplate(uint8_t buffer, const uint8_t* data, size_t len) {
  const uint8_t cmd[] = {0x09, buffer};  // DownChar
  const uint8_t code = command(cmd, sizeof(cmd));
  if (code != R307::OK) return code;

  for (size_t off = 0; off < len; off += packetLen) {
    const size_t n = min((size_t)packetLen, len - off);
    const bool last = off + n >= len;
    writePacket(last ? PID_END : PID_DATA, data + off, n);
  }
  ser.flush();
  delay(20);
  return R307::OK;
}
