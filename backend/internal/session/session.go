package session

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const MinAgeToKick = 24 * time.Hour
const MinInactivitySeconds = 3600
const MaxInactivitySeconds = 365 * 24 * 3600

var ErrSessionTooNew = errors.New("session_too_new")
var ErrRevoked = errors.New("session_revoked")
var ErrInvalidPolicy = errors.New("invalid_policy")

type Handler struct {
	DB *pgxpool.Pool
}

func NewHandler(db *pgxpool.Pool) *Handler {
	return &Handler{DB: db}
}

func (h *Handler) Create(ctx context.Context, userID, deviceName, platform string) (string, error) {
	var id string
	err := h.DB.QueryRow(ctx,
		`INSERT INTO sessions (user_id, device_name, platform) VALUES ($1, $2, $3) RETURNING id`,
		userID, deviceName, platform,
	).Scan(&id)
	return id, err
}

func (h *Handler) sweepInactive(ctx context.Context, userID string) error {
	_, err := h.DB.Exec(ctx, `
		UPDATE sessions
		SET revoked_at = now()
		WHERE user_id = $1
		  AND revoked_at IS NULL
		  AND last_seen_at < now() - make_interval(secs => (SELECT session_inactivity_seconds FROM users WHERE id = $1))`,
		userID)
	return err
}

func (h *Handler) IsValid(ctx context.Context, sessionID, userID string) (bool, error) {
	if err := h.sweepInactive(ctx, userID); err != nil {
		return false, err
	}
	var revoked bool
	err := h.DB.QueryRow(ctx,
		`UPDATE sessions SET last_seen_at = now()
		 WHERE id = $1 AND user_id = $2
		 RETURNING (revoked_at IS NOT NULL)`,
		sessionID, userID,
	).Scan(&revoked)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return !revoked, nil
}

type Info struct {
	ID         string     `json:"id"`
	DeviceName string     `json:"device_name"`
	Platform   string     `json:"platform"`
	CreatedAt  time.Time  `json:"created_at"`
	LastSeenAt time.Time  `json:"last_seen_at"`
	Current    bool       `json:"current"`
	RevokedAt  *time.Time `json:"revoked_at,omitempty"`
}

func (h *Handler) List(ctx context.Context, userID, currentSessionID string) ([]Info, error) {
	if err := h.sweepInactive(ctx, userID); err != nil {
		return nil, err
	}
	rows, err := h.DB.Query(ctx, `
		SELECT id, device_name, platform, created_at, last_seen_at, revoked_at
		FROM sessions
		WHERE user_id = $1 AND revoked_at IS NULL
		ORDER BY last_seen_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Info
	for rows.Next() {
		var info Info
		if err := rows.Scan(&info.ID, &info.DeviceName, &info.Platform, &info.CreatedAt, &info.LastSeenAt, &info.RevokedAt); err != nil {
			continue
		}
		info.Current = info.ID == currentSessionID
		results = append(results, info)
	}
	return results, nil
}

func (h *Handler) GetPolicy(ctx context.Context, userID string) (int, error) {
	var seconds int
	err := h.DB.QueryRow(ctx, `SELECT session_inactivity_seconds FROM users WHERE id = $1`, userID).Scan(&seconds)
	return seconds, err
}

func (h *Handler) SetPolicy(ctx context.Context, userID string, seconds int) error {
	if seconds < MinInactivitySeconds || seconds > MaxInactivitySeconds {
		return ErrInvalidPolicy
	}
	_, err := h.DB.Exec(ctx, `UPDATE users SET session_inactivity_seconds = $1 WHERE id = $2`, seconds, userID)
	return err
}

func (h *Handler) assertCanKick(ctx context.Context, actingSessionID string) error {
	var createdAt time.Time
	err := h.DB.QueryRow(ctx, `SELECT created_at FROM sessions WHERE id = $1`, actingSessionID).Scan(&createdAt)
	if err != nil {
		return err
	}
	if time.Since(createdAt) < MinAgeToKick {
		return ErrSessionTooNew
	}
	return nil
}

func (h *Handler) Revoke(ctx context.Context, userID, actingSessionID, targetSessionID string) error {
	if err := h.assertCanKick(ctx, actingSessionID); err != nil {
		return err
	}
	_, err := h.DB.Exec(ctx,
		`UPDATE sessions SET revoked_at = now() WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL`,
		targetSessionID, userID)
	return err
}

func (h *Handler) RevokeAllOthers(ctx context.Context, userID, actingSessionID string) error {
	if err := h.assertCanKick(ctx, actingSessionID); err != nil {
		return err
	}
	_, err := h.DB.Exec(ctx,
		`UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND id != $2 AND revoked_at IS NULL`,
		userID, actingSessionID)
	return err
}
