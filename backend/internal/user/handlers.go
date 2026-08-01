package user

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

type userInfo struct {
	ID       string `json:"id"`
	Username string `json:"username"`
}

// Search looks up users by exact or partial username, used to start a new DM.
func (h *Handler) Search(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	if q == "" {
		json.NewEncoder(w).Encode([]userInfo{})
		return
	}
	rows, err := h.DB.Query(context.Background(),
		`SELECT id, username FROM users WHERE username ILIKE $1 LIMIT 20`, "%"+q+"%")
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	results := []userInfo{}
	for rows.Next() {
		var u userInfo
		if err := rows.Scan(&u.ID, &u.Username); err != nil {
			continue
		}
		results = append(results, u)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(results)
}

// Get returns basic public info for a single user by id, used by clients
// to render conversation lists (peer username, group member names).
func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var u userInfo
	err := h.DB.QueryRow(context.Background(), `SELECT id, username FROM users WHERE id = $1`, id).Scan(&u.ID, &u.Username)
	if err != nil {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(u)
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(userInfo{ID: claims.UserID, Username: claims.Username})
}
