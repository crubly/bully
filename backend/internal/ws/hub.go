package ws

import (
	"context"
	"encoding/json"
	"log"
	"sync"

	"github.com/redis/go-redis/v9"
)

const pubsubChannel = "bully:relay"

type Envelope struct {
	Type           string `json:"type"`
	ConversationID string `json:"conversation_id"`
	FromUserID     string `json:"from_user_id"`
	ToUserID       string `json:"to_user_id"`
	MessageID      string `json:"message_id,omitempty"`
	Ciphertext     string `json:"ciphertext,omitempty"`
	Header         string `json:"header,omitempty"`
}

type Hub struct {
	redis *redis.Client

	mu    sync.RWMutex
	conns map[string]*Conn
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
