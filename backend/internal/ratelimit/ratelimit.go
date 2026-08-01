package ratelimit

import (
	"context"
	"net"
	"net/http"
	"time"

	"github.com/redis/go-redis/v9"
)

// PerIP rate-limits requests using a Redis fixed-window counter keyed by
// client IP + route, shared across backend instances. Guards auth endpoints
// against brute-force / registration-spam without needing sticky sessions.
func PerIP(rdb *redis.Client, routeKey string, limit int, window int) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := clientIP(r)
			key := "ratelimit:" + routeKey + ":" + ip
			ctx := context.Background()

			count, err := rdb.Incr(ctx, key).Result()
			if err != nil {
				// Fail open on Redis hiccups rather than locking everyone out.
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
	// Behind a reverse proxy X-Forwarded-For would need trusting a specific
	// proxy hop; for a directly-exposed node RemoteAddr is authoritative.
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
