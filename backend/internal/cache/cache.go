package cache

import (
	"context"

	"github.com/redis/go-redis/v9"
)

func Connect(ctx context.Context, addr string) (*redis.Client, error) {
	client := redis.NewClient(&redis.Options{Addr: addr})
	if err := client.Ping(ctx).Err(); err != nil {
		return nil, err
	}
	return client, nil
}
