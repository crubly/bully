package convo

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"bully/backend/internal/auth"
)

type Handler struct {
	DB *pgxpool.Pool
}

func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{DB: db}
}

type createDMRequest struct {
	PeerUserID string `json:"peer_user_id"`
}

type conversationResponse struct {
	ID   string `json:"id"`
	Kind string `json:"kind"`
}

// CreateDM creates (or returns existing) 1-on-1 conversation between the
// caller and peer. No key material is exchanged here — that happens
// end-to-end between the clients once both are members.
func (h *Handler) CreateDM(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var req createDMRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PeerUserID == "" {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}

	ctx := context.Background()

	var existing string
	err := h.DB.QueryRow(ctx, `
		SELECT c.id FROM conversations c
		JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = $1
		JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = $2
		WHERE c.kind = 'dm'
		LIMIT 1`, claims.UserID, req.PeerUserID).Scan(&existing)
	if err == nil {
		json.NewEncoder(w).Encode(conversationResponse{ID: existing, Kind: "dm"})
		return
	}

	tx, err := h.DB.Begin(ctx)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(ctx)

	var convoID string
	if err := tx.QueryRow(ctx,
		`INSERT INTO conversations (kind) VALUES ('dm') RETURNING id`,
	).Scan(&convoID); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
		convoID, claims.UserID, req.PeerUserID,
	); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if err := tx.Commit(ctx); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(conversationResponse{ID: convoID, Kind: "dm"})
}

type createGroupRequest struct {
	Name    string   `json:"name"`
	Members []string `json:"member_user_ids"`
}

type groupResponse struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	ConversationID string `json:"conversation_id"`
}

func (h *Handler) CreateGroup(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var req createGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}

	ctx := context.Background()
	tx, err := h.DB.Begin(ctx)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(ctx)

	var groupID string
	if err := tx.QueryRow(ctx,
		`INSERT INTO groups (name, owner_id) VALUES ($1, $2) RETURNING id`,
		req.Name, claims.UserID,
	).Scan(&groupID); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	var convoID string
	if err := tx.QueryRow(ctx,
		`INSERT INTO conversations (kind, group_id) VALUES ('group', $1) RETURNING id`, groupID,
	).Scan(&convoID); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	if _, err := tx.Exec(ctx,
		`INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'owner')`,
		groupID, claims.UserID,
	); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2)`,
		convoID, claims.UserID,
	); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	for _, memberID := range req.Members {
		if memberID == claims.UserID {
			continue
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'member')`,
			groupID, memberID,
		); err != nil {
			http.Error(w, "db error", http.StatusInternalServerError)
			return
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2)`,
			convoID, memberID,
		); err != nil {
			http.Error(w, "db error", http.StatusInternalServerError)
			return
		}
	}

	if err := tx.Commit(ctx); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(groupResponse{ID: groupID, Name: req.Name, ConversationID: convoID})
}

type conversationListItem struct {
	ID        string  `json:"id"`
	Kind      string  `json:"kind"`
	GroupID   *string `json:"group_id,omitempty"`
	GroupName *string `json:"group_name,omitempty"`
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	rows, err := h.DB.Query(context.Background(), `
		SELECT c.id, c.kind, c.group_id, g.name FROM conversations c
		JOIN conversation_members m ON m.conversation_id = c.id
		LEFT JOIN groups g ON g.id = c.group_id
		WHERE m.user_id = $1
		ORDER BY c.created_at`, claims.UserID)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	results := []conversationListItem{}
	for rows.Next() {
		var item conversationListItem
		if err := rows.Scan(&item.ID, &item.Kind, &item.GroupID, &item.GroupName); err != nil {
			continue
		}
		results = append(results, item)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(results)
}

// Members returns the member IDs of a conversation, used by clients to know
// who to run Double Ratchet / Sender Keys handshakes with. Only callers who
// are themselves members may list them.
func (h *Handler) Members(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conversationID := chi.URLParam(r, "id")

	ctx := context.Background()
	isMember, err := IsMember(ctx, h, conversationID, claims.UserID)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if !isMember {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}

	ids, err := MemberIDs(ctx, h, conversationID)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ids)
}
