// Package mobilebridge 把特斯拉车辆协议暴露给 iOS（gomobile）。
// Swift 只负责 CoreBluetooth 收发，加密/签名/会话全部复用官方 Go 实现。
package mobilebridge

import (
	"context"
	"os"
	"sync"
	"time"

	"github.com/teslamotors/vehicle-command/pkg/connector"
	"github.com/teslamotors/vehicle-command/pkg/protocol"
	"github.com/teslamotors/vehicle-command/pkg/vehicle"
)

// pipe 实现 connector.Connector，用 channel 把 BLE 字节流接进来
type pipe struct {
	vin    string
	rx     chan []byte
	tx     chan []byte
	closed chan struct{}
	once   sync.Once
}

func (p *pipe) Receive() <-chan []byte { return p.rx }

func (p *pipe) Send(ctx context.Context, buf []byte) error {
	b := make([]byte, len(buf))
	copy(b, buf)
	select {
	case p.tx <- b:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-p.closed:
		return context.Canceled
	}
}

func (p *pipe) VIN() string { return p.vin }

func (p *pipe) Close() {
	p.once.Do(func() { close(p.closed) })
}

func (p *pipe) PreferredAuthMethod() connector.AuthMethod { return connector.AuthMethodGCM }
func (p *pipe) RetryInterval() time.Duration             { return time.Second }
func (p *pipe) AllowedLatency() time.Duration            { return 2 * time.Second }

// Session 是 Swift 侧操作的句柄
type Session struct {
	p       *pipe
	car     *vehicle.Vehicle
	mu      sync.Mutex
	lastErr string
}

// NewSession 用 PEM 私钥创建会话
func NewSession(vin string, keyPEM string) (*Session, error) {
	f, err := os.CreateTemp("", "tesla-key-*.pem")
	if err != nil {
		return nil, err
	}
	name := f.Name()
	if _, err := f.WriteString(keyPEM); err != nil {
		f.Close()
		os.Remove(name)
		return nil, err
	}
	f.Close()
	defer os.Remove(name)

	priv, err := protocol.LoadPrivateKey(name)
	if err != nil {
		return nil, err
	}

	p := &pipe{
		vin:    vin,
		rx:     make(chan []byte, 64),
		tx:     make(chan []byte, 64),
		closed: make(chan struct{}),
	}
	car, err := vehicle.NewVehicle(p, priv, nil)
	if err != nil {
		return nil, err
	}
	return &Session{p: p, car: car}, nil
}

// Enqueue 把车辆发来的 BLE 通知数据送进协议栈
func (s *Session) Enqueue(data []byte) {
	b := make([]byte, len(data))
	copy(b, data)
	select {
	case s.p.rx <- b:
	default:
	}
}

// Dequeue 非阻塞取出待写入蓝牙的数据（没有则返回空）
func (s *Session) Dequeue() []byte {
	select {
	case b := <-s.p.tx:
		return b
	default:
		return nil
	}
}

// WaitDequeue 阻塞等待待发送数据，最多 millis 毫秒
func (s *Session) WaitDequeue(millis int) []byte {
	t := time.Duration(millis) * time.Millisecond
	if t <= 0 {
		return s.Dequeue()
	}
	select {
	case b := <-s.p.tx:
		return b
	case <-time.After(t):
		return nil
	}
}

func (s *Session) LastError() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.lastErr
}

func (s *Session) run(fn func(context.Context) error) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	if err := fn(ctx); err != nil {
		s.mu.Lock()
		s.lastErr = err.Error()
		s.mu.Unlock()
		return false
	}
	return true
}

func (s *Session) Unlock() bool { return s.run(s.car.Unlock) }
func (s *Session) Lock() bool   { return s.run(s.car.Lock) }
func (s *Session) Drive() bool  { return s.run(s.car.RemoteDrive) }

func (s *Session) Close() {
	s.p.Close()
	s.car.Disconnect()
}
