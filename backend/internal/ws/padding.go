package ws

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
)

const (
	FrameSize          = 2048
	frameHeaderBytes   = 3
	MaxPayloadPerFrame = FrameSize - frameHeaderBytes

	flagIsReal  byte = 1 << 0
	flagHasMore byte = 1 << 1
)

var errPayloadTooLarge = errors.New("payload exceeds one frame and fragmentation slice is wrong")

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

func DummyFrame() ([]byte, error) {
	frame := make([]byte, FrameSize)
	if _, err := rand.Read(frame); err != nil {
		return nil, err
	}
	frame[0] = 0
	return frame, nil
}

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
