package ratelimit

import (
	"context"
	"net"
	"net/http"
	"time"

	"github.com/redis/go-redis/v9"
)

func PerIP(rdb *redis.Client, routeKey string, limit int, window int) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := clientIP(r)
			key := "ratelimit:" + routeKey + ":" + ip
			ctx := context.Background()

			count, err := rdb.Incr(ctx, key).Result()
			if err != nil {

				next.ServeHTTP(w, r)
				return
			}
			if count == 1 {
				rdb.Expire(ctx, key, time.Duration(window)*time.Second)
			}
			if count > int64(limit) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusTooManyRequests)
				w.Write([]byte(`{"error":"rate_limited"}`))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func clientIP(r *http.Request) string {

	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
