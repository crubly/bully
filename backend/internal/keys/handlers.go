package keys

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"bully/backend/internal/auth"
)

// Handler manages X25519 PUBLIC prekeys only. Private keys never leave the
// client; these bundles let a client start a Double Ratchet session with a
// peer who is currently offline (X3DH-style async handshake).
type Handler struct {
	DB *pgxpool.Pool
}

func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{DB: db}
}

type uploadRequest struct {
	SignedKeyID  int    `json:"signed_key_id"`
	SignedPubKey string `json:"signed_public_key"`
	Signature    string `json:"signature"`
	OneTimeKeys  []struct {
		KeyID     int    `json:"key_id"`
		PublicKey string `json:"public_key"`
	} `json:"one_time_keys"`
}

func (h *Handler) Upload(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var req uploadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
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

	if req.SignedPubKey != "" {
		_, err = tx.Exec(ctx,
			`INSERT INTO prekeys (user_id, key_id, public_key, signature, is_signed)
			 VALUES ($1, $2, $3, $4, true)
			 ON CONFLICT (user_id, key_id) DO UPDATE SET public_key = $3, signature = $4`,
			claims.UserID, req.SignedKeyID, req.SignedPubKey, req.Signature)
		if err != nil {
			http.Error(w, "db error", http.StatusInternalServerError)
			return
		}
	}
	for _, k := range req.OneTimeKeys {
		_, err = tx.Exec(ctx,
			`INSERT INTO prekeys (user_id, key_id, public_key, is_signed)
			 VALUES ($1, $2, $3, false)
			 ON CONFLICT (user_id, key_id) DO NOTHING`,
			claims.UserID, k.KeyID, k.PublicKey)
		if err != nil {
			http.Error(w, "db error", http.StatusInternalServerError)
			return
		}
	}
	if err := tx.Commit(ctx); err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type bundleResponse struct {
	SignedPublicKey string  `json:"signed_public_key,omitempty"`
	Signature       string  `json:"signature,omitempty"`
	OneTimeKeyID    *int    `json:"one_time_key_id,omitempty"`
	OneTimePublic   *string `json:"one_time_public_key,omitempty"`
}

// Bundle fetches the target user's signed prekey plus (and consumes) one
// unused one-time prekey, for a fresh async Double Ratchet handshake.
func (h *Handler) Bundle(w http.ResponseWriter, r *http.Request) {
	targetID := r.URL.Query().Get("user_id")
	if targetID == "" {
		http.Error(w, "user_id required", http.StatusBadRequest)
		return
	}
	ctx := context.Background()
	var resp bundleResponse

	err := h.DB.QueryRow(ctx,
		`SELECT public_key, signature FROM prekeys WHERE user_id = $1 AND is_signed = true LIMIT 1`,
		targetID,
	).Scan(&resp.SignedPublicKey, &resp.Signature)
	if err != nil && err != pgx.ErrNoRows {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	tx, err := h.DB.Begin(ctx)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(ctx)

	var keyID int
	var pubKey string
	err = tx.QueryRow(ctx,
		`SELECT key_id, public_key FROM prekeys
		 WHERE user_id = $1 AND is_signed = false AND used = false
		 ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`,
		targetID,
	).Scan(&keyID, &pubKey)
	if err == nil {
		_, _ = tx.Exec(ctx, `UPDATE prekeys SET used = true WHERE user_id = $1 AND key_id = $2`, targetID, keyID)
		resp.OneTimeKeyID = &keyID
		resp.OneTimePublic = &pubKey
		_ = tx.Commit(ctx)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
