package relay

import (
	"context"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"

	"bully/backend/internal/auth"
	"bully/backend/internal/convo"
	"bully/backend/internal/session"
	"bully/backend/internal/ws"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,

	CheckOrigin: func(r *http.Request) bool { return true },
}

type Handler struct {
	DB        *pgxpool.Pool
	Hub       *ws.Hub
	Convo     *convo.Handler
	Sessions  *session.Handler
	Offline   *OfflineQueue
	JWTSecret string
}

func NewHandler(db *pgxpool.Pool, hub *ws.Hub, convoHandler *convo.Handler, sessions *session.Handler, offline *OfflineQueue, jwtSecret string) *Handler {
	return &Handler{DB: db, Hub: hub, Convo: convoHandler, Sessions: sessions, Offline: offline, JWTSecret: jwtSecret}
}

func (h *Handler) Serve(w http.ResponseWriter, r *http.Request) {
	tokenStr := r.URL.Query().Get("token")
	claims, err := auth.ParseToken(h.JWTSecret, tokenStr)
	if err != nil {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}
	valid, err := h.Sessions.IsValid(r.Context(), claims.SessionID, claims.UserID)
	if err != nil || !valid {
		http.Error(w, "session revoked", http.StatusUnauthorized)
		return
	}

	wsConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("relay: upgrade failed: %v", err)
		return
	}

	conn := ws.NewConn(claims.UserID, wsConn)
	h.Hub.Register(claims.UserID, conn)
	defer h.Hub.Unregister(claims.UserID)

	go conn.WritePump()
	h.deliverOffline(r.Context(), claims.UserID, conn)
	conn.ReadPump(func(env ws.Envelope) {
		h.handleInbound(r.Context(), env)
	})
}

func (h *Handler) handleInbound(ctx context.Context, env ws.Envelope) {
	if env.Type == "direct" {

		if env.ToUserID == "" {
			return
		}
		h.Hub.Deliver(ctx, env)
		return
	}
	if env.Type == "call_signal" || env.Type == "avatar" {

		if env.ToUserID == "" {
			return
		}
		isMember, err := convo.IsMember(ctx, h.Convo, env.ConversationID, env.FromUserID)
		if err != nil || !isMember {
			log.Printf("relay: rejected %s from %s (not a member of %s)", env.Type, env.FromUserID, env.ConversationID)
			return
		}
		h.Hub.Deliver(ctx, env)
		return
	}
	if env.Type != "message" {
		return
	}
	isMember, err := convo.IsMember(ctx, h.Convo, env.ConversationID, env.FromUserID)
	if err != nil || !isMember {
		log.Printf("relay: rejected message from %s to conversation %s (not a member)", env.FromUserID, env.ConversationID)
		return
	}

	messageID, err := h.Offline.Enqueue(ctx, env)
	if err != nil {
		log.Printf("relay: enqueue failed: %v", err)
		return
	}
	env.MessageID = messageID

	members, err := convo.MemberIDs(ctx, h.Convo, env.ConversationID)
	if err != nil {
		log.Printf("relay: member lookup failed: %v", err)
		return
	}
	for _, memberID := range members {
		if memberID == env.FromUserID {
			continue
		}
		out := env
		out.ToUserID = memberID
		h.Hub.Deliver(ctx, out)
	}
}

func (h *Handler) deliverOffline(ctx context.Context, userID string, conn *ws.Conn) {
	rows, err := h.DB.Query(ctx, `SELECT conversation_id FROM conversation_members WHERE user_id = $1`, userID)
	if err != nil {
		log.Printf("relay: offline conversation lookup failed: %v", err)
		return
	}
	var conversationIDs []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err == nil {
			conversationIDs = append(conversationIDs, id)
		}
	}
	rows.Close()

	for _, convID := range conversationIDs {
		envs, err := h.Offline.ForConversation(ctx, convID)
		if err != nil {
			log.Printf("relay: offline queue read failed for %s: %v", convID, err)
			continue
		}
		for _, env := range envs {
			env.ToUserID = userID
			conn.Send(env)
		}
	}
}
