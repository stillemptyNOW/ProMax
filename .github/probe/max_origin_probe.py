import asyncio
import json
import secrets
import struct

import msgpack
import websockets

ENDPOINT = "wss://api.oneme.ru/websocket"
ORIGINS = ["https://web.max.ru", "https://stillemptynow.github.io", None]
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
)


def frame(seq, opcode, payload):
    body = msgpack.packb(payload)
    header = struct.pack(">BBhhB", 10, 0, seq, opcode, 0) + len(body).to_bytes(3, "big")
    return header + body


def parse(data):
    if isinstance(data, str):
        return {"text": data[:200]}
    cmd = data[1]
    seq, opcode = struct.unpack(">hh", data[2:6])
    length = int.from_bytes(data[7:10], "big")
    payload = None
    if length and data[6] == 0:
        try:
            payload = msgpack.unpackb(data[10 : 10 + length], strict_map_key=False)
        except Exception as error:
            payload = f"undecodable: {error}"
    elif length:
        payload = f"compressed {length} bytes"
    summary = payload
    if isinstance(payload, dict):
        summary = {k: (v if isinstance(v, (str, int, bool)) else type(v).__name__) for k, v in payload.items()}
    return {"cmd": cmd, "seq": seq, "opcode": opcode, "payload": summary}


async def probe(origin):
    headers = {"User-Agent": USER_AGENT}
    if origin:
        headers["Origin"] = origin
    try:
        async with websockets.connect(
            ENDPOINT, additional_headers=headers, open_timeout=20, max_size=None
        ) as socket:
            await socket.send(
                frame(
                    1,
                    6,
                    {
                        "userAgent": {
                            "deviceType": "WEB",
                            "locale": "ru",
                            "deviceLocale": "ru",
                            "osVersion": "Windows",
                            "deviceName": "Chrome",
                            "headerUserAgent": USER_AGENT,
                            "appVersion": "26.8.8",
                            "screen": "1080x1920 1.0x",
                            "timezone": "Europe/Moscow",
                        },
                        "deviceId": secrets.token_hex(16),
                    },
                )
            )
            reply = await asyncio.wait_for(socket.recv(), timeout=20)
            return {"origin": origin, "connected": True, "reply": parse(reply)}
    except websockets.InvalidStatus as error:
        return {"origin": origin, "connected": False, "http_status": error.response.status_code}
    except Exception as error:
        return {"origin": origin, "connected": False, "error": f"{type(error).__name__}: {error}"}


async def main():
    for origin in ORIGINS:
        print(json.dumps(await probe(origin), ensure_ascii=False, default=str))


asyncio.run(main())
