package httpsafety

import "net/http"

// MaxBody caps request body size so a client can't exhaust server memory
// with an oversized payload (JSON bomb / slow-body DoS).
func MaxBody(limitBytes int64) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			r.Body = http.MaxBytesReader(w, r.Body, limitBytes)
			next.ServeHTTP(w, r)
		})
	}
}

// SecurityHeaders sets a minimal, low-risk set of headers appropriate for a
// JSON API (no HTML is ever served, so this isn't a full CSP policy).
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		next.ServeHTTP(w, r)
	})
}
