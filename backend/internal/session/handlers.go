package session

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"bully/backend/internal/auth"
)

func writeErr(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": code})
}

func (h *Handler) ListHTTP(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	list, err := h.List(r.Context(), claims.UserID, claims.SessionID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "db_error")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(list)
}

func (h *Handler) RevokeHTTP(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	targetID := chi.URLParam(r, "id")
	err := h.Revoke(r.Context(), claims.UserID, claims.SessionID, targetID)
	if errors.Is(err, ErrSessionTooNew) {
		writeErr(w, http.StatusForbidden, "session_too_new")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "db_error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) RevokeAllHTTP(w http.ResponseWriter, r *http.Request) {
	claims := auth.FromContext(r.Context())
	if claims == nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	err := h.RevokeAllOthers(r.Context(), claims.UserID, claims.SessionID)
	if errors.Is(err, ErrSessionTooNew) {
		writeErr(w, http.StatusForbidden, "session_too_new")
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "db_error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
