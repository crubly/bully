package convo

import "context"

func IsMember(ctx context.Context, h *Handler, conversationID, userID string) (bool, error) {
	var exists bool
	err := h.DB.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2)`,
		conversationID, userID,
	).Scan(&exists)
	return exists, err
}

func MemberIDs(ctx context.Context, h *Handler, conversationID string) ([]string, error) {
	rows, err := h.DB.Query(ctx,
		`SELECT user_id FROM conversation_members WHERE conversation_id = $1`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	ids := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			continue
		}
		ids = append(ids, id)
	}
	return ids, nil
}
