package iceservers

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"bully/backend/internal/auth"
)

const credentialTTL = 2 * time.Hour

type Handler struct {
	TURNHost   string
	TURNSecret string
}

func NewHandler(turnHost, turnSecret string) *Handler {
	return &Handler{TURNHost: turnHost, TURNSecret: turnSecret}
}

type iceServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

func (h *Handler) Serve(w http.ResponseWriter, r *http.Request) {
	if auth.FromContext(r.Context()) == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	username := fmt.Sprintf("%d", time.Now().Add(credentialTTL).Unix())
	mac := hmac.New(sha1.New, []byte(h.TURNSecret))
	mac.Write([]byte(username))
	credential := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	servers := []iceServer{
		{URLs: []string{fmt.Sprintf("stun:%s:3478", h.TURNHost)}},
		{
			URLs:       []string{fmt.Sprintf("turn:%s:3478?transport=udp", h.TURNHost), fmt.Sprintf("turn:%s:3478?transport=tcp", h.TURNHost)},
			Username:   username,
			Credential: credential,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"ice_servers": servers})
}
