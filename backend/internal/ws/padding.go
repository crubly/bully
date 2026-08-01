package ws

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
)

// Frame layout (fixed FrameSize bytes total, sent as one binary WS message):
//
//	byte 0     : flags — bit0 = isReal (0 = cover/dummy traffic), bit1 = hasMore fragments
//	bytes 1-2  : uint16 BE payload length in THIS frame
//	bytes 3..  : payload bytes, then random padding out to FrameSize
//
// Every tick, in both directions, exactly one frame goes out — real data if
// there's a queued message (fragmented across ticks if it doesn't fit), a
// random-padded dummy frame otherwise. To anyone on the network path who
// can see packet timing/size but not content (a LAN router, an ISP, a
// Tailscale DERP relay when it can't establish direct P2P), every tick
// looks identical whether or not a message was actually relayed at that
// moment.
const (
	FrameSize          = 2048
	frameHeaderBytes   = 3
	MaxPayloadPerFrame = FrameSize - frameHeaderBytes

	flagIsReal  byte = 1 << 0
	flagHasMore byte = 1 << 1
)

var errPayloadTooLarge = errors.New("payload exceeds one frame and fragmentation slice is wrong")

// EncodeFrame builds one fixed-size frame carrying up to MaxPayloadPerFrame
// bytes of payload. hasMore indicates more fragments of the same logical
// message follow on subsequent ticks.
func EncodeFrame(payload []byte, hasMore bool) ([]byte, error) {
	if len(payload) > MaxPayloadPerFrame {
		return nil, errPayloadTooLarge
	}
	frame := make([]byte, FrameSize)
	if _, err := rand.Read(frame); err != nil {
		return nil, err
	}
	flags := flagIsReal
	if hasMore {
		flags |= flagHasMore
	}
	frame[0] = flags
	binary.BigEndian.PutUint16(frame[1:3], uint16(len(payload)))
	copy(frame[frameHeaderBytes:], payload)
	return frame, nil
}

// DummyFrame builds one fixed-size frame of pure random padding — bitwise
// indistinguishable in size from a real frame, with isReal=0 so the
// receiver discards it without touching the fragment-assembly buffer.
func DummyFrame() ([]byte, error) {
	frame := make([]byte, FrameSize)
	if _, err := rand.Read(frame); err != nil {
		return nil, err
	}
	frame[0] = 0
	return frame, nil
}

// DecodeFrame extracts (payload, isReal, hasMore) from one fixed-size frame.
func DecodeFrame(frame []byte) (payload []byte, isReal bool, hasMore bool, err error) {
	if len(frame) != FrameSize {
		return nil, false, false, errors.New("unexpected frame size")
	}
	flags := frame[0]
	isReal = flags&flagIsReal != 0
	hasMore = flags&flagHasMore != 0
	length := binary.BigEndian.Uint16(frame[1:3])
	if int(length) > MaxPayloadPerFrame {
		return nil, false, false, errors.New("corrupt frame length")
	}
	payload = frame[frameHeaderBytes : frameHeaderBytes+int(length)]
	return payload, isReal, hasMore, nil
}

// SplitIntoFrames fragments an arbitrary-length message across as many
// fixed-size frames as needed.
func SplitIntoFrames(message []byte) ([][]byte, error) {
	if len(message) == 0 {
		frame, err := EncodeFrame(nil, false)
		if err != nil {
			return nil, err
		}
		return [][]byte{frame}, nil
	}
	var frames [][]byte
	for offset := 0; offset < len(message); offset += MaxPayloadPerFrame {
		end := offset + MaxPayloadPerFrame
		if end > len(message) {
			end = len(message)
		}
		hasMore := end < len(message)
		frame, err := EncodeFrame(message[offset:end], hasMore)
		if err != nil {
			return nil, err
		}
		frames = append(frames, frame)
	}
	return frames, nil
}
