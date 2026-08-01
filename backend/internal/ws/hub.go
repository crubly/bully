package ws

import (
	"context"
	"encoding/json"
	"log"
	"sync"

	"github.com/redis/go-redis/v9"
)

const pubsubChannel = "bully:relay"

// Envelope is the opaque relay unit: server routes it by ToUserID without
// ever inspecting Ciphertext/Header contents.
type Envelope struct {
	Type           string `json:"type"` // "message" | "ack" | "presence"
	ConversationID string `json:"conversation_id"`
	FromUserID     string `json:"from_user_id"`
	ToUserID       string `json:"to_user_id"`
	MessageID      string `json:"message_id,omitempty"`
	Ciphertext     string `json:"ciphertext,omitempty"`
	Header         string `json:"header,omitempty"`
}

// Hub tracks local WebSocket connections and fans out envelopes to the
// right connection, using Redis pub/sub so multiple backend instances can
// deliver to a user connected to a different instance.
type Hub struct {
	redis *redis.Client

	mu    sync.RWMutex
	conns map[string]*Conn // userID -> local connection
}

func NewHub(rdb *redis.Client) *Hub {
	h := &Hub{redis: rdb, conns: make(map[string]*Conn)}
	go h.subscribeLoop()
	return h
}

func (h *Hub) Register(userID string, c *Conn) {
	h.mu.Lock()
	h.conns[userID] = c
	h.mu.Unlock()
}

func (h *Hub) Unregister(userID string) {
	h.mu.Lock()
	delete(h.conns, userID)
	h.mu.Unlock()
}

func (h *Hub) localConn(userID string) *Conn {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.conns[userID]
}

// Deliver attempts local delivery first; if the target isn't connected to
// this instance, publish via Redis so whichever instance holds their
// connection can deliver it.
func (h *Hub) Deliver(ctx context.Context, env Envelope) {
	if c := h.localConn(env.ToUserID); c != nil {
		c.Send(env)
		return
	}
	payload, err := json.Marshal(env)
	if err != nil {
		log.Printf("ws: marshal envelope: %v", err)
		return
	}
	if err := h.redis.Publish(ctx, pubsubChannel, payload).Err(); err != nil {
		log.Printf("ws: publish envelope: %v", err)
	}
}

func (h *Hub) subscribeLoop() {
	ctx := context.Background()
	sub := h.redis.Subscribe(ctx, pubsubChannel)
	ch := sub.Channel()
	for msg := range ch {
		var env Envelope
		if err := json.Unmarshal([]byte(msg.Payload), &env); err != nil {
			continue
		}
		if c := h.localConn(env.ToUserID); c != nil {
			c.Send(env)
		}
	}
}
