package selftest

import (
	"bytes"
	"encoding/hex"
	"fmt"

	"golang.org/x/crypto/argon2"
)

// katExpectHex: Argon2id(password="password", salt="somesalt", t=2, m=64*1024, p=1, len=32).
const (
	katPassword  = "password"
	katSalt      = "somesalt"
	katTime      = 2
	katMemory    = 64 * 1024
	katThreads   = 1
	katKeyLen    = 32
	katExpectHex = "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7"
)

func RunCryptoSelfTest() error {
	if err := argon2idRoundTrip(); err != nil {
		return fmt.Errorf("argon2id round-trip: %w", err)
	}
	return nil
}

func argon2idRoundTrip() error {
	hash := argon2.IDKey([]byte(katPassword), []byte(katSalt), katTime, katMemory, katThreads, katKeyLen)
	want, err := hex.DecodeString(katExpectHex)
	if err != nil {
		return fmt.Errorf("decode expected KAT hex: %w", err)
	}
	if !bytes.Equal(hash, want) {
		return fmt.Errorf("known-answer mismatch: got %x, want %x", hash, want)
	}

	salt := []byte("round-trip-salt-")
	h1 := argon2.IDKey([]byte("correct horse"), salt, 1, 64*1024, 4, 32)
	h2 := argon2.IDKey([]byte("correct horse"), salt, 1, 64*1024, 4, 32)
	if !bytes.Equal(h1, h2) {
		return fmt.Errorf("argon2id is not deterministic for identical inputs")
	}
	h3 := argon2.IDKey([]byte("wrong horse"), salt, 1, 64*1024, 4, 32)
	if bytes.Equal(h1, h3) {
		return fmt.Errorf("argon2id produced identical output for different passwords")
	}
	return nil
}
