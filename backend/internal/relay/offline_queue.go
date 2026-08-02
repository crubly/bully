package relay

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"time"

	"github.com/redis/go-redis/v9"

	"bully/backend/internal/ws"
)

func newMessageID() string {
	buf := make([]byte, 16)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}

const (
	offlineQueueMaxLen = 500
	offlineQueueTTL    = 14 * 24 * time.Hour
)

type OfflineQueue struct {
	redis *redis.Client
}

func NewOfflineQueue(rdb *redis.Client) *OfflineQueue {
	return &OfflineQueue{redis: rdb}
}

func offlineQueueKey(conversationID string) string {
	return "offline:" + conversationID
}

// Enqueue stores an envelope's ciphertext in Redis only — never Postgres —
// so undelivered messages live in memory with a TTL instead of persisting
// indefinitely on disk. The relay only ever sees ciphertext/header, same as
// before; this just changes where that opaque blob sits while queued.
func (q *OfflineQueue) Enqueue(ctx context.Context, env ws.Envelope) (string, error) {
	if env.MessageID == "" {
		env.MessageID = newMessageID()
	}
	payload, err := json.Marshal(env)
	if err != nil {
		return "", err
	}
	key := offlineQueueKey(env.ConversationID)
	pipe := q.redis.TxPipeline()
	pipe.RPush(ctx, key, payload)
	pipe.LTrim(ctx, key, -offlineQueueMaxLen, -1)
	pipe.Expire(ctx, key, offlineQueueTTL)
	_, err = pipe.Exec(ctx)
	return env.MessageID, err
}

func (q *OfflineQueue) ForConversation(ctx context.Context, conversationID string) ([]ws.Envelope, error) {
	raw, err := q.redis.LRange(ctx, offlineQueueKey(conversationID), 0, -1).Result()
	if err != nil {
		return nil, err
	}
	envs := make([]ws.Envelope, 0, len(raw))
	for _, item := range raw {
		var env ws.Envelope
		if err := json.Unmarshal([]byte(item), &env); err != nil {
			continue
		}
		envs = append(envs, env)
	}
	return envs, nil
}
