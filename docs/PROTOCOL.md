# Device ↔ App protocol (BLE)

The ESP32 exposes one GATT service with two characteristics:

| Name    | UUID                                   | Direction     | Property      |
|---------|----------------------------------------|---------------|---------------|
| Service | `a7e1f000-5b2c-4c8a-9d1e-0f1a2b3c4d5e` |               |               |
| Command | `a7e1f001-5b2c-4c8a-9d1e-0f1a2b3c4d5e` | app → device  | write         |
| Event   | `a7e1f002-5b2c-4c8a-9d1e-0f1a2b3c4d5e` | device → app  | notify        |

**Framing:** both directions carry UTF-8 JSON, **one object per line, ending in `\n`**.
A line can be split across several BLE packets (MTU), so each side buffers bytes until it
sees a newline. Templates (~700 base64 chars) therefore fit in a single message.

The device advertises as `FP-Scanner-XXXX` (last bytes of its MAC address).

## Commands (app → device)

| Command | Fields | Reply event(s) |
|---|---|---|
| `INFO` | | `INFO` |
| `SET_TIME` | `ts` (Unix seconds) | `TIME_OK` |
| `CLEAR` | | `CLEAR_OK` — empties the sensor library |
| `LOAD` | `slot` (1…cap), `tpl` (base64 template) | `LOAD_OK {slot}` |
| `ENROLL` | | `PLACE`, `CAPTURE`, `LIFT`, `POOR_IMAGE` …, then `ENROLL_OK` or `ENROLL_FAIL` |
| `CANCEL` / `IDLE` | | `MODE {mode:"idle"}` |
| `VERIFY_MODE` | `session` (UUID) | `MODE {mode:"verify"}`, then `MATCH` / `NO_MATCH` per finger |
| `SYNC` | `session` | `MATCH {replay:true}` for every logged scan of that session, then `SYNC_DONE {count}` |
| `CLEAR_LOG` | | `LOG_CLEARED` |

Any failure produces `ERROR {msg, code?}`.

## Events (device → app)

```jsonc
{"evt":"INFO","id":"FP-Scanner-1A2B","fw":"1.0.0","cap":999,"count":42,"sensor":true,"bat":82}
{"evt":"PLACE","n":1}                 // waiting for finger, capture n of 3
{"evt":"CAPTURE","n":1}               // capture n succeeded
{"evt":"LIFT"}                        // lift finger before next capture
{"evt":"POOR_IMAGE"}                  // capture unreadable, will retry
{"evt":"ENROLL_OK","tpl":"<base64>","score":180}
{"evt":"ENROLL_FAIL","reason":"mismatch|verify|timeout|upload"}
{"evt":"MATCH","slot":27,"score":142,"ts":1759650000,"dup":false}
{"evt":"NO_MATCH"}
{"evt":"SYNC_DONE","count":12}
{"evt":"ERROR","msg":"store failed","code":24}
```

## Session flow

1. App downloads the course roster + templates from Supabase.
2. `CLEAR`, then one `LOAD` per student with a fingerprint (slots 1…N). The app keeps the
   slot → student map for this session only.
3. `VERIFY_MODE {session}`. Each finger → `MATCH {slot, ts}` → app marks Present/Late and
   queues the record for upload.
4. The device also appends every match to `/scans.log` in flash. If Bluetooth drops, it
   keeps recording. On reconnect (and at session end) the app sends `SYNC` and receives
   the missed scans.
5. `IDLE`; the app calls `close_session()` in the database, which marks everyone else absent.

## Why templates are not kept on the sensor

R307 holds ~1000 templates, AS608 ~300, R503 ~200 — fewer than the number of students.
Keeping templates in the database and loading one course per session removes that limit
and lets any device be used in any hall.
