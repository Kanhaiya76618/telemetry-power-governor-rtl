import asyncio
import json
import os
import threading
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Optional

import serial
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


UART_BAUD = int(os.getenv("PWRGOV_BAUD", "115200"))
UART_PORT = os.getenv("PWRGOV_PORT", "COM14")
FRAME_LEN = 16
FRAME_HEADER = bytes([0xAA, 0x55])


@dataclass
class TelemetryState:
    ts: float = 0.0
    connected: bool = False
    frame_counter: int = 0
    host_mode: int = 0
    alarm_a: int = 0
    alarm_b: int = 0
    clk_en_a: int = 0
    clk_en_b: int = 0
    grant_a: int = 0
    grant_b: int = 0
    current_budget: int = 0
    budget_headroom: int = 0
    efficiency: int = 0
    temp_a: int = 0
    temp_b: int = 0
    act_a: int = 0
    stall_a: int = 0
    act_b: int = 0
    stall_b: int = 0
    req_a: int = 0
    req_b: int = 0
    phase: int = 0


class ControlPayload(BaseModel):
    mode: Optional[str] = Field(default=None, description="internal|host")
    host_use_ext_budget: Optional[bool] = None
    budget: Optional[int] = Field(default=None, ge=0, le=7)
    req_a: Optional[int] = Field(default=None, ge=0, le=3)
    req_b: Optional[int] = Field(default=None, ge=0, le=3)
    act_a: Optional[bool] = None
    stall_a: Optional[bool] = None
    act_b: Optional[bool] = None
    stall_b: Optional[bool] = None
    temp_a: Optional[int] = Field(default=None, ge=0, le=127)
    temp_b: Optional[int] = Field(default=None, ge=0, le=127)


class SerialBridge:
    def __init__(self, port: str, baud: int):
        self.port = port
        self.baud = baud
        self._ser: Optional[serial.Serial] = None
        self._buf = bytearray()
        self._lock = threading.Lock()
        self.state = TelemetryState()
        self._running = False

    def start(self) -> None:
        self._running = True
        t = threading.Thread(target=self._run, daemon=True)
        t.start()

    def stop(self) -> None:
        self._running = False
        with self._lock:
            if self._ser and self._ser.is_open:
                self._ser.close()

    def _open(self) -> None:
        with self._lock:
            if self._ser and self._ser.is_open:
                return
            self._ser = serial.Serial(self.port, self.baud, timeout=0.05)
            self.state.connected = True

    def _run(self) -> None:
        while self._running:
            try:
                self._open()
                data = self._ser.read(256) if self._ser else b""
                if data:
                    self._buf.extend(data)
                    self._consume_frames()
            except Exception:
                self.state.connected = False
                time.sleep(1.0)

    def _consume_frames(self) -> None:
        while True:
            idx = self._buf.find(FRAME_HEADER)
            if idx < 0:
                if len(self._buf) > 512:
                    self._buf.clear()
                return
            if idx > 0:
                del self._buf[:idx]
            if len(self._buf) < FRAME_LEN:
                return
            frame = bytes(self._buf[:FRAME_LEN])
            if frame[15] != 0x0D:
                del self._buf[0]
                continue
            checksum = 0
            for b in frame[2:14]:
                checksum ^= b
            if checksum != frame[14]:
                del self._buf[0]
                continue
            self._decode(frame)
            del self._buf[:FRAME_LEN]

    def _decode(self, frame: bytes) -> None:
        flags = frame[4]
        grants = frame[5]
        budget = frame[6]
        eff = frame[7] | ((frame[8] & 0x03) << 8)
        io_flags = frame[11]
        req_pack = frame[12]

        self.state = TelemetryState(
            ts=time.time(),
            connected=True,
            frame_counter=(frame[3] << 8) | frame[2],
            host_mode=(flags >> 0) & 0x01,
            alarm_a=(flags >> 1) & 0x01,
            alarm_b=(flags >> 2) & 0x01,
            clk_en_a=(flags >> 3) & 0x01,
            clk_en_b=(flags >> 4) & 0x01,
            grant_a=(grants >> 0) & 0x03,
            grant_b=(grants >> 2) & 0x03,
            current_budget=(budget >> 0) & 0x07,
            budget_headroom=(budget >> 3) & 0x07,
            efficiency=eff,
            temp_a=frame[9],
            temp_b=frame[10],
            stall_a=(io_flags >> 0) & 0x01,
            act_a=(io_flags >> 1) & 0x01,
            stall_b=(io_flags >> 2) & 0x01,
            act_b=(io_flags >> 3) & 0x01,
            req_a=(req_pack >> 0) & 0x03,
            req_b=(req_pack >> 2) & 0x03,
            phase=frame[13] & 0x07,
        )

    def write_commands(self, commands: List[int]) -> None:
        with self._lock:
            if not self._ser or not self._ser.is_open:
                raise RuntimeError("Serial not connected")
            self._ser.write(bytes(commands))


def payload_to_commands(p: ControlPayload) -> List[int]:
    cmds: List[int] = []

    if p.mode is not None:
        if p.mode not in {"internal", "host"}:
            raise HTTPException(status_code=400, detail="mode must be 'internal' or 'host'")
        cmds.append(0xA1 if p.mode == "host" else 0xA0)

    if p.host_use_ext_budget is not None:
        cmds.append(0xF1 if p.host_use_ext_budget else 0xF0)

    if p.budget is not None:
        cmds.append(0xB0 | (p.budget & 0x07))

    if p.req_a is not None:
        cmds.append(0xC0 | (p.req_a & 0x03))

    if p.req_b is not None:
        cmds.append(0xC4 | (p.req_b & 0x03))

    if p.act_a is not None:
        cmds.append(0xD1 if p.act_a else 0xD0)

    if p.stall_a is not None:
        cmds.append(0xD3 if p.stall_a else 0xD2)

    if p.act_b is not None:
        cmds.append(0xD5 if p.act_b else 0xD4)

    if p.stall_b is not None:
        cmds.append(0xD7 if p.stall_b else 0xD6)

    if p.temp_a is not None:
        cmds.extend([0xE0, p.temp_a & 0x7F])

    if p.temp_b is not None:
        cmds.extend([0xE1, p.temp_b & 0x7F])

    return cmds


app = FastAPI(title="PwrGov Laptop Bridge", version="0.1.0")
bridge = SerialBridge(UART_PORT, UART_BAUD)
websockets: List[WebSocket] = []


@app.on_event("startup")
async def startup() -> None:
    bridge.start()
    asyncio.create_task(broadcast_loop())


@app.on_event("shutdown")
def shutdown() -> None:
    bridge.stop()


@app.get("/api/state")
def get_state() -> Dict:
    return asdict(bridge.state)


@app.post("/api/control")
def post_control(payload: ControlPayload) -> Dict:
    commands = payload_to_commands(payload)
    if not commands:
        return {"ok": True, "sent": 0}
    try:
        bridge.write_commands(commands)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {"ok": True, "sent": len(commands), "commands": [hex(c) for c in commands]}


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    websockets.append(ws)
    try:
        while True:
            await asyncio.sleep(60)
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        if ws in websockets:
            websockets.remove(ws)


async def broadcast_loop() -> None:
    while True:
        if websockets:
            msg = json.dumps(asdict(bridge.state))
            dead = []
            for ws in websockets:
                try:
                    await ws.send_text(msg)
                except Exception:
                    dead.append(ws)
            for ws in dead:
                if ws in websockets:
                    websockets.remove(ws)
        await asyncio.sleep(0.2)


static_dir = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=static_dir), name="static")


@app.get("/")
def root() -> FileResponse:
    return FileResponse(static_dir / "index.html")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=False)
