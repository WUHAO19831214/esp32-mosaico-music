"""Standalone ESP-Claw HTTP/WebSocket transport (standard library only)."""
import base64
import os
import socket
import struct
import urllib.request
LOCAL_HTTP=urllib.request.build_opener(urllib.request.ProxyHandler({}))

class WebIM:
    """Minimal read-only WebSocket subscriber for native device-agent replies."""
    def __init__(self,host):
        self.sock=socket.create_connection((host,80),timeout=10)
        key=base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f'GET /ws/webim HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
        self.buffer=b''
        while b'\r\n\r\n' not in self.buffer:self.buffer+=self.sock.recv(4096)
        header,self.buffer=self.buffer.split(b'\r\n\r\n',1)
        assert header.startswith(b'HTTP/1.1 101'),header
    def readn(self,n):
        while len(self.buffer)<n:
            part=self.sock.recv(65536)
            if not part:raise ConnectionError('Device WebSocket closed')
            self.buffer+=part
        out,self.buffer=self.buffer[:n],self.buffer[n:];return out
    def frame(self):
        a,b=self.readn(2);n=b&127
        if n==126:n=struct.unpack('!H',self.readn(2))[0]
        elif n==127:n=struct.unpack('!Q',self.readn(8))[0]
        assert n<=2*1024*1024
        mask=self.readn(4) if b&128 else None;body=self.readn(n)
        if mask:body=bytes(x^mask[i%4] for i,x in enumerate(body))
        return a&15,body
    def close(self):self.sock.close()

