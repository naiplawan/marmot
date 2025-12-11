package main

import (
	"context"
	"runtime"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/mem"
)

func collectMemory() (MemoryStatus, error) {
	vm, err := mem.VirtualMemory()
	if err != nil {
		return MemoryStatus{}, err
	}

	swap, _ := mem.SwapMemory()
	pressure := getMemoryPressure()

	return MemoryStatus{
		Used:        vm.Used,
		Total:       vm.Total,
		UsedPercent: vm.UsedPercent,
		SwapUsed:    swap.Used,
		SwapTotal:   swap.Total,
		Pressure:    pressure,
	}, nil
}

func getMemoryPressure() string {
	if runtime.GOOS == "darwin" {
		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancel()
		out, err := runCmd(ctx, "memory_pressure")
		if err != nil {
			return ""
		}
		lower := strings.ToLower(out)
		if strings.Contains(lower, "critical") {
			return "critical"
		}
		if strings.Contains(lower, "warn") {
			return "warn"
		}
		if strings.Contains(lower, "normal") {
			return "normal"
		}
		return ""
	}

	// Linux: Calculate memory pressure based on available memory
	vm, err := mem.VirtualMemory()
	if err != nil {
		return ""
	}

	// Use available percentage to determine pressure
	availablePercent := (vm.Available * 100) / vm.Total

	if availablePercent < 5 {
		return "critical"
	} else if availablePercent < 15 {
		return "warn"
	} else {
		return "normal"
	}
}
