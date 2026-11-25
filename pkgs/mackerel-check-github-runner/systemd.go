package main

import (
	"context"
	"fmt"

	"github.com/coreos/go-systemd/v22/dbus"
)

// subStateFunc reports the systemd sub state of a unit.
type subStateFunc func(ctx context.Context, unit string) (string, error)

// systemdSubState asks systemd over D-Bus for the sub state of a unit.
func systemdSubState(ctx context.Context, unit string) (string, error) {
	conn, err := dbus.NewSystemConnectionContext(ctx)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	property, err := conn.GetUnitPropertyContext(ctx, unit, "SubState")
	if err != nil {
		return "", err
	}
	value := property.Value.Value()
	subState, ok := value.(string)
	if !ok {
		return "", fmt.Errorf("unexpected SubState type %T", value)
	}
	return subState, nil
}
