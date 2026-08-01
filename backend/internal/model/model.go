package model

import "time"

type User struct {
	ID           string    `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"created_at"`
}

type Prekey struct {
	ID        string `json:"id"`
	UserID    string `json:"user_id"`
	KeyID     int    `json:"key_id"`
	PublicKey string `json:"public_key"`
	Signature string `json:"signature,omitempty"`
	IsSigned  bool   `json:"is_signed"`
	Used      bool   `json:"used"`
}

type Group struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	OwnerID   string    `json:"owner_id"`
	CreatedAt time.Time `json:"created_at"`
}

type GroupMember struct {
	GroupID string `json:"group_id"`
	UserID  string `json:"user_id"`
	Role    string `json:"role"`
}

type Conversation struct {
	ID        string    `json:"id"`
	Kind      string    `json:"kind"` // "dm" | "group"
	GroupID   *string   `json:"group_id,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

// Message is an opaque relay envelope. The server never inspects Ciphertext
// or Header contents beyond routing them to conversation members.
type Message struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversation_id"`
	SenderID       string    `json:"sender_id"`
	Ciphertext     string    `json:"ciphertext"`
	Header         string    `json:"header"`
	CreatedAt      time.Time `json:"created_at"`
}
