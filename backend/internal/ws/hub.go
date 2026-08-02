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
	conns map[string][]*Conn
}

func NewHub(rdb *redis.Client) *Hub {
	h := &Hub{redis: rdb, conns: make(map[string][]*Conn)}
	go h.subscribeLoop()
	return h
}

// Register adds a connection for userID without evicting that user's other
// active devices, so a phone and a laptop signed into the same account can
// both stay reachable at once.
func (h *Hub) Register(userID string, c *Conn) {
	h.mu.Lock()
	h.conns[userID] = append(h.conns[userID], c)
	h.mu.Unlock()
}

func (h *Hub) Unregister(userID string, c *Conn) {
	h.mu.Lock()
	conns := h.conns[userID]
	for i, existing := range conns {
		if existing == c {
			h.conns[userID] = append(conns[:i], conns[i+1:]...)
			break
		}
	}
	if len(h.conns[userID]) == 0 {
		delete(h.conns, userID)
	}
	h.mu.Unlock()
}

func (h *Hub) localConns(userID string) []*Conn {
	h.mu.RLock()
	defer h.mu.RUnlock()
	conns := h.conns[userID]
	if len(conns) == 0 {
		return nil
	}
	out := make([]*Conn, len(conns))
	copy(out, conns)
	return out
}

// Deliver fans an envelope out to every currently-connected device of the
// recipient (so e.g. two devices logged into the same account both get a
// call signal or a live message), falling back to cross-node Redis pub/sub
// only when the recipient has no connection on this node at all.
func (h *Hub) Deliver(ctx context.Context, env Envelope) {
	if conns := h.localConns(env.ToUserID); len(conns) > 0 {
		for _, c := range conns {
			c.Send(env)
		}
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
		for _, c := range h.localConns(env.ToUserID) {
			c.Send(env)
		}
	}
}
