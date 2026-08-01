package ws

import (
	"encoding/json"
	"log"
	"time"

	"github.com/gorilla/websocket"
)

// TickInterval is how often a frame (real or cover) goes out in each
// direction. Lower = less added latency but more constant bandwidth
// overhead; this is the core privacy/cost tradeoff of constant-rate padding.
const TickInterval = 200 * time.Millisecond

// Conn wraps a single user's WebSocket connection with a buffered outbound
// queue, framed and paced by padding.go so traffic timing/size stays
// constant regardless of whether anything real is being sent.
type Conn struct {
	userID string
	ws     *websocket.Conn
	send   chan []byte // raw JSON envelope bytes, pre-fragmentation
}

// sendBufferSize is generous because the constant-rate pump only drains one
// message per TickInterval — a burst (e.g. offline history replay on
// reconnect) must queue reliably rather than get silently dropped just
// because it can't all go out in the same instant.
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

// WritePump emits exactly one frame per tick: the next fragment of a queued
// message if there is one, otherwise a random-padded dummy frame.
func (c *Conn) WritePump() {
	defer c.ws.Close()
	ticker := time.NewTicker(TickInterval)
	defer ticker.Stop()

	var pending []byte // bytes of the message currently being fragmented out
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

// ReadPump reassembles fixed-size frames back into full envelopes and hands
// each complete one to handle. Dummy (cover) frames are silently dropped.
// Returns when the connection closes.
func (c *Conn) ReadPump(handle func(Envelope)) {
	defer c.ws.Close()
	var assembly []byte
	for {
		msgType, raw, err := c.ws.ReadMessage()
		if err != nil {
			return
		}
		if msgType != websocket.BinaryMessage || len(raw) != FrameSize {
			continue // not a frame we understand — ignore rather than desync
		}
		payload, isReal, hasMore, err := DecodeFrame(raw)
		if err != nil {
			continue
		}
		if !isReal {
			continue // cover traffic
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
