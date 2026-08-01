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

// Serve issues short-lived TURN credentials using coturn's standard
// "TURN REST API" convention (username = expiry timestamp, password =
// base64(HMAC-SHA1(secret, username))) so the shared TURN_SECRET itself
// never has to reach the client. Calls are forced through this relay
// (iceTransportPolicy: "relay" client-side) rather than attempted P2P, so a
// LAN router only ever observes traffic to this trusted node, never the
// other participant's IP.
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
