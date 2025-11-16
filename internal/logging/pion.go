package logging

import (
	"strings"

	"github.com/pion/logging"
	"github.com/rs/zerolog"
)

type pionLogger struct {
	logger    *zerolog.Logger
	subsystem string
}

// Print all messages except trace.
func (c pionLogger) Trace(msg string) {
	c.logger.Trace().Msg(msg)
}
func (c pionLogger) Tracef(format string, args ...any) {
	c.logger.Trace().Msgf(format, args...)
}

func (c pionLogger) Debug(msg string) {
	c.logger.Debug().Msg(msg)
}
func (c pionLogger) Debugf(format string, args ...any) {
	c.logger.Debug().Msgf(format, args...)
}
func (c pionLogger) Info(msg string) {
	c.logger.Info().Msg(msg)
}
func (c pionLogger) Infof(format string, args ...any) {
	c.logger.Info().Msgf(format, args...)
}
func (c pionLogger) Warn(msg string) {
	// Filter out noisy ICE warnings during normal connection establishment
	if c.subsystem == "ice" && strings.Contains(msg, "Failed to ping without candidate pairs") {
		// This is normal during ICE gathering, downgrade to debug
		c.logger.Debug().Msg(msg)
		return
	}
	c.logger.Warn().Msg(msg)
}
func (c pionLogger) Warnf(format string, args ...any) {
	// Filter out noisy ICE warnings during normal connection establishment
	if c.subsystem == "ice" {
		formatted := strings.TrimSpace(format)
		if strings.Contains(formatted, "Failed to ping without candidate pairs") {
			// This is normal during ICE gathering, downgrade to debug
			c.logger.Debug().Msgf(format, args...)
			return
		}
	}
	c.logger.Warn().Msgf(format, args...)
}
func (c pionLogger) Error(msg string) {
	c.logger.Error().Msg(msg)
}
func (c pionLogger) Errorf(format string, args ...any) {
	c.logger.Error().Msgf(format, args...)
}

// customLoggerFactory satisfies the interface logging.LoggerFactory
// This allows us to create different loggers per subsystem. So we can
// add custom behavior.
type pionLoggerFactory struct{}

func (c pionLoggerFactory) NewLogger(subsystem string) logging.LeveledLogger {
	logger := rootLogger.getLogger(subsystem).With().
		Str("scope", "pion").
		Str("component", subsystem).
		Logger()

	return pionLogger{logger: &logger, subsystem: subsystem}
}

var defaultLoggerFactory = &pionLoggerFactory{}

func GetPionDefaultLoggerFactory() logging.LoggerFactory {
	return defaultLoggerFactory
}
