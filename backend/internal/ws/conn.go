package ws

import (
	"encoding/json"
	"log"
	"time"

	"github.com/gorilla/websocket"
)

const TickInterval = 200 * time.Millisecond

type Conn struct {
	userID string
	ws     *websocket.Conn
	send   chan []byte
}

const sendBufferSize = 4096

func NewConn(userID string, wsConn *websocket.Conn) *Conn {
	return &Conn{userID: userID, ws: wsConn, send: make(chan []byte, sendBufferSize)}
}

func (c *Conn) Send(env Envelope) {
	raw, err := json.Marshal(env)
	if err != nil {
		log.Printf("ws: marshal envelope for user %s: %v", c.userID, err)
		return
	}
	select {
	case c.send <- raw:
	default:
		log.Printf("ws: send buffer full for user %s, dropping", c.userID)
	}
}

func (c *Conn) WritePump() {
	defer c.ws.Close()
	ticker := time.NewTicker(TickInterval)
	defer ticker.Stop()

	var pending []byte
	for range ticker.C {
		if len(pending) == 0 {
			select {
			case raw := <-c.send:
				pending = raw
			default:
			}
		}

		var frame []byte
		var err error
		if len(pending) > 0 {
			end := len(pending)
			if end > MaxPayloadPerFrame {
				end = MaxPayloadPerFrame
			}
			hasMore := end < len(pending)
			frame, err = EncodeFrame(pending[:end], hasMore)
			pending = pending[end:]
		} else {
			frame, err = DummyFrame()
		}
		if err != nil {
			log.Printf("ws: frame encode failed for user %s: %v", c.userID, err)
			return
		}
		if err := c.ws.WriteMessage(websocket.BinaryMessage, frame); err != nil {
			return
		}
	}
}

func (c *Conn) ReadPump(handle func(Envelope)) {
	defer c.ws.Close()
	var assembly []byte
	for {
		msgType, raw, err := c.ws.ReadMessage()
		if err != nil {
			return
		}
		if msgType != websocket.BinaryMessage || len(raw) != FrameSize {
			continue
		}
		payload, isReal, hasMore, err := DecodeFrame(raw)
		if err != nil {
			continue
		}
		if !isReal {
			continue
		}
		assembly = append(assembly, payload...)
		if hasMore {
			continue
		}

		var env Envelope
		if err := json.Unmarshal(assembly, &env); err != nil {
			assembly = nil
			continue
		}
		assembly = nil
		env.FromUserID = c.userID
		handle(env)
	}
}
