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
	// Relay is opaque ciphertext; allow cross-origin so the Flutter web
	// client (served from a different origin during dev) can connect.
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Handler struct {
	DB        *pgxpool.Pool
	Hub       *ws.Hub
	Convo     *convo.Handler
	Sessions  *session.Handler
	JWTSecret string
}

func NewHandler(db *pgxpool.Pool, hub *ws.Hub, convoHandler *convo.Handler, sessions *session.Handler, jwtSecret string) *Handler {
	return &Handler{DB: db, Hub: hub, Convo: convoHandler, Sessions: sessions, JWTSecret: jwtSecret}
}

// Serve upgrades the connection after validating the token passed as the
// "token" query param (browsers can't set custom headers on the WS
// handshake), then wires read/write pumps into the hub.
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
		// Point-to-point control channel used for group Sender Key
		// distribution: delivered straight to ToUserID, never persisted and
		// not gated on conversation membership (the "conversation" here is a
		// synthetic per-member-pair ID the clients agree on locally, not a
		// real row). Payload is opaque ciphertext exactly like "message".
		if env.ToUserID == "" {
			return
		}
		h.Hub.Deliver(ctx, env)
		return
	}
	if env.Type == "call_signal" {
		// Point-to-point WebRTC signaling (SDP/ICE), E2E encrypted by the
		// client the same way chat messages are — the relay never persists
		// it and never sees plaintext. Still gated on conversation
		// membership so only actual contacts/group members can ring someone.
		if env.ToUserID == "" {
			return
		}
		isMember, err := convo.IsMember(ctx, h.Convo, env.ConversationID, env.FromUserID)
		if err != nil || !isMember {
			log.Printf("relay: rejected call_signal from %s (not a member of %s)", env.FromUserID, env.ConversationID)
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

	var messageID string
	err = h.DB.QueryRow(ctx,
		`INSERT INTO messages (conversation_id, sender_id, ciphertext, header)
		 VALUES ($1, $2, $3, $4) RETURNING id`,
		env.ConversationID, env.FromUserID, env.Ciphertext, env.Header,
	).Scan(&messageID)
	if err != nil {
		log.Printf("relay: persist failed: %v", err)
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

// deliverOffline replays any messages the connecting user missed while
// disconnected, in conversations they belong to, oldest first.
func (h *Handler) deliverOffline(ctx context.Context, userID string, conn *ws.Conn) {
	rows, err := h.DB.Query(ctx, `
		SELECT m.id, m.conversation_id, m.sender_id, m.ciphertext, m.header
		FROM messages m
		JOIN conversation_members cm ON cm.conversation_id = m.conversation_id
		WHERE cm.user_id = $1
		ORDER BY m.created_at ASC
		LIMIT 500`, userID)
	if err != nil {
		log.Printf("relay: offline replay query failed: %v", err)
		return
	}
	defer rows.Close()

	for rows.Next() {
		var env ws.Envelope
		if err := rows.Scan(&env.MessageID, &env.ConversationID, &env.FromUserID, &env.Ciphertext, &env.Header); err != nil {
			continue
		}
		env.Type = "message"
		env.ToUserID = userID
		conn.Send(env)
	}
}
