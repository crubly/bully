package auth

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var usernameRe = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)

// Sessions is satisfied by *session.Handler. Declared here (rather than
// importing the session package) to avoid an import cycle, since session's
// HTTP handlers need auth.FromContext.
type Sessions interface {
	Create(ctx context.Context, userID, deviceName, platform string) (string, error)
	IsValid(ctx context.Context, sessionID, userID string) (bool, error)
}

type Handler struct {
	DB       *pgxpool.Pool
	Secret   string
	Sessions Sessions
}

func NewHandler(db *pgxpool.Pool, secret string, sessions Sessions) *Handler {
	return &Handler{DB: db, Secret: secret, Sessions: sessions}
}

type registerRequest struct {
	Username   string `json:"username"`
	Password   string `json:"password"`
	DeviceName string `json:"device_name"`
	Platform   string `json:"platform"`
}

type authResponse struct {
	Token    string `json:"token"`
	UserID   string `json:"user_id"`
	Username string `json:"username"`
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid body")
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	if !usernameRe.MatchString(req.Username) {
		writeErr(w, http.StatusBadRequest, "username must be 3-32 chars, alphanumeric/underscore")
		return
	}
	if len(req.Password) < 8 {
		writeErr(w, http.StatusBadRequest, "password must be at least 8 characters")
		return
	}

	hash, err := HashPassword(req.Password)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "hash error")
		return
	}

	var userID string
	err = h.DB.QueryRow(context.Background(),
		`INSERT INTO users (username, password_hash) VALUES ($1, $2) RETURNING id`,
		req.Username, hash,
	).Scan(&userID)
	if err != nil {
		writeErr(w, http.StatusConflict, "username already taken")
		return
	}

	sessionID, err := h.Sessions.Create(context.Background(), userID, deviceLabel(req.DeviceName), deviceLabel(req.Platform))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "session error")
		return
	}
	token, err := IssueToken(h.Secret, userID, req.Username, sessionID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "token error")
		return
	}
	writeJSON(w, http.StatusCreated, authResponse{Token: token, UserID: userID, Username: req.Username})
}

func deviceLabel(v string) string {
	if v == "" {
		return "Unknown"
	}
	return v
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid body")
		return
	}

	var userID, hash string
	err := h.DB.QueryRow(context.Background(),
		`SELECT id, password_hash FROM users WHERE username = $1`, req.Username,
	).Scan(&userID, &hash)
	if err == pgx.ErrNoRows {
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	} else if err != nil {
		writeErr(w, http.StatusInternalServerError, "db error")
		return
	}

	ok, err := VerifyPassword(req.Password, hash)
	if err != nil || !ok {
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	sessionID, err := h.Sessions.Create(context.Background(), userID, deviceLabel(req.DeviceName), deviceLabel(req.Platform))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "session error")
		return
	}
	token, err := IssueToken(h.Secret, userID, req.Username, sessionID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "token error")
		return
	}
	writeJSON(w, http.StatusOK, authResponse{Token: token, UserID: userID, Username: req.Username})
}

// Middleware validates the Bearer token and stashes claims in the request context.
type contextKey string

const ClaimsContextKey contextKey = "claims"

func (h *Handler) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hdr := r.Header.Get("Authorization")
		if !strings.HasPrefix(hdr, "Bearer ") {
			writeErr(w, http.StatusUnauthorized, "missing token")
			return
		}
		tokenStr := strings.TrimPrefix(hdr, "Bearer ")
		claims, err := ParseToken(h.Secret, tokenStr)
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "invalid token")
			return
		}
		valid, err := h.Sessions.IsValid(r.Context(), claims.SessionID, claims.UserID)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "session check failed")
			return
		}
		if !valid {
			writeErr(w, http.StatusUnauthorized, "session revoked")
			return
		}
		ctx := context.WithValue(r.Context(), ClaimsContextKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func FromContext(ctx context.Context) *Claims {
	claims, _ := ctx.Value(ClaimsContextKey).(*Claims)
	return claims
}
