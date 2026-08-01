package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"

	"bully/backend/internal/auth"
	"bully/backend/internal/cache"
	"bully/backend/internal/config"
	"bully/backend/internal/convo"
	"bully/backend/internal/db"
	"bully/backend/internal/httpsafety"
	"bully/backend/internal/iceservers"
	"bully/backend/internal/keys"
	"bully/backend/internal/ratelimit"
	"bully/backend/internal/relay"
	"bully/backend/internal/session"
	"bully/backend/internal/user"
	"bully/backend/internal/ws"
)

const maxRequestBody = 1 << 20 // 1 MiB — plenty for JSON API bodies, blocks payload-bomb DoS

func main() {
	cfg := config.Load()
	ctx := context.Background()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatalf("migrate db: %v", err)
	}

	rdb, err := cache.Connect(ctx, cfg.RedisAddr)
	if err != nil {
		log.Fatalf("connect redis: %v", err)
	}
	defer rdb.Close()

	hub := ws.NewHub(rdb)

	sessionHandler := session.NewHandler(pool)
	authHandler := auth.NewHandler(pool, cfg.JWTSecret, sessionHandler)
	userHandler := user.NewHandler(pool)
	keysHandler := keys.NewHandler(pool)
	convoHandler := convo.NewHandler(pool)
	relayHandler := relay.NewHandler(pool, hub, convoHandler, sessionHandler, cfg.JWTSecret)
	iceHandler := iceservers.NewHandler(cfg.TURNHost, cfg.TURNSecret)

	r := chi.NewRouter()
	r.Use(httpsafety.SecurityHeaders)
	r.Use(httpsafety.MaxBody(maxRequestBody))

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	// Public, unauthenticated: lets a client verify "is this address a real
	// Bully node" and show a human-readable name before ever asking for
	// credentials (see the client's node-picker screen).
	r.Get("/node/info", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"bully_node": true,
			"name":       cfg.NodeName,
		})
	})

	authRateLimit := ratelimit.PerIP(rdb, "auth", 20, 60) // 20 attempts/min/IP
	r.With(authRateLimit).Post("/auth/register", authHandler.Register)
	r.With(authRateLimit).Post("/auth/login", authHandler.Login)

	r.Group(func(r chi.Router) {
		r.Use(authHandler.Middleware)
		r.Get("/users/search", userHandler.Search)
		r.Get("/users/me", userHandler.Me)
		r.Get("/users/{id}", userHandler.Get)
		r.Post("/keys/upload", keysHandler.Upload)
		r.Get("/keys/bundle", keysHandler.Bundle)
		r.Post("/conversations/dm", convoHandler.CreateDM)
		r.Post("/conversations/group", convoHandler.CreateGroup)
		r.Get("/conversations", convoHandler.List)
		r.Get("/conversations/{id}/members", convoHandler.Members)
		r.Get("/sessions", sessionHandler.ListHTTP)
		r.Delete("/sessions/{id}", sessionHandler.RevokeHTTP)
		r.Post("/sessions/revoke-all", sessionHandler.RevokeAllHTTP)
		r.Get("/ice-servers", iceHandler.Serve)
	})

	// Token passed as a query param since the WS handshake can't carry a
	// custom Authorization header from browsers; validated inside Serve.
	r.Get("/ws", relayHandler.Serve)

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
		// No global WriteTimeout/IdleTimeout: the WS endpoint holds
		// long-lived connections by design (including the constant-rate
		// padding heartbeat), which a blanket timeout would kill.
	}

	log.Printf("bully backend (%s) listening on :%s", cfg.NodeName, cfg.Port)
	if err := server.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
