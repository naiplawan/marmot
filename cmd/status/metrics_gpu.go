package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
)

const (
	systemProfilerTimeout = 4 * time.Second
	macGPUInfoTTL         = 10 * time.Minute
	powermetricsTimeout   = 2 * time.Second
)

// Pre-compiled regex patterns for GPU usage parsing
var (
	gpuActiveResidencyRe = regexp.MustCompile(`GPU HW active residency:\s+([\d.]+)%`)
	gpuIdleResidencyRe   = regexp.MustCompile(`GPU idle residency:\s+([\d.]+)%`)
)

func (c *Collector) collectGPU(now time.Time) ([]GPUStatus, error) {
	// macOS specific GPU collection
	if runtime.GOOS == "darwin" {
		// Get static GPU info (cached for 10 min)
		if len(c.cachedGPU) == 0 || c.lastGPUAt.IsZero() || now.Sub(c.lastGPUAt) >= macGPUInfoTTL {
			if gpus, err := readMacGPUInfo(); err == nil && len(gpus) > 0 {
				c.cachedGPU = gpus
				c.lastGPUAt = now
			}
		}

		// Get real-time GPU usage
		if len(c.cachedGPU) > 0 {
			usage := getMacGPUUsage()
			result := make([]GPUStatus, len(c.cachedGPU))
			copy(result, c.cachedGPU)
			// Apply usage to first GPU (Apple Silicon has one integrated GPU)
			if len(result) > 0 {
				result[0].Usage = usage
			}
			return result, nil
		}
	}

	// Linux GPU collection
	ctx, cancel := context.WithTimeout(context.Background(), 600*time.Millisecond)
	defer cancel()

	// Try NVIDIA GPUs first
	if commandExists("nvidia-smi") {
		out, err := runCmd(ctx, "nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,name", "--format=csv,noheader,nounits")
		if err == nil {
			return parseNvidiaOutput(out), nil
		}
	}

	// Try AMD GPUs
	if commandExists("rocm-smi") {
		out, err := runCmd(ctx, "rocm-smi", "--showuse", "--showmem", "--showtemp")
		if err == nil {
			return parseRocmOutput(out), nil
		}
	}

	// Try Intel GPUs (Linux integrated graphics)
	if gpus, err := readIntelGPUInfo(); err == nil && len(gpus) > 0 {
		return gpus, nil
	}

	return []GPUStatus{{
		Name: "No GPU metrics available",
		Note: "Install nvidia-smi, rocm-smi, or enable Intel GPU drivers",
	}}, nil
}

func parseNvidiaOutput(out string) []GPUStatus {
	lines := strings.Split(strings.TrimSpace(out), "\n")
	var gpus []GPUStatus
	for _, line := range lines {
		fields := strings.Split(line, ",")
		if len(fields) < 4 {
			continue
		}
		util, _ := strconv.ParseFloat(strings.TrimSpace(fields[0]), 64)
		memUsed, _ := strconv.ParseFloat(strings.TrimSpace(fields[1]), 64)
		memTotal, _ := strconv.ParseFloat(strings.TrimSpace(fields[2]), 64)
		name := strings.TrimSpace(fields[3])

		gpus = append(gpus, GPUStatus{
			Name:        name,
			Usage:       util,
			MemoryUsed:  memUsed,
			MemoryTotal: memTotal,
		})
	}

	if len(gpus) == 0 {
		return []GPUStatus{{
			Name: "NVIDIA GPU read failed",
			Note: "Verify nvidia-smi availability and GPU presence",
		}}
	}

	return gpus
}

func parseRocmOutput(out string) []GPUStatus {
	lines := strings.Split(out, "\n")
	var gpus []GPUStatus

	for _, line := range lines {
		if strings.Contains(line, "GPU use") {
			// Parse usage: "GPU use (%)                  : 15.2"
			if parts := strings.Fields(line); len(parts) >= 5 {
				if usage, err := strconv.ParseFloat(parts[4], 64); err == nil {
					gpus = append(gpus, GPUStatus{
						Name:  "AMD GPU",
						Usage: usage,
						Note:  "Detected via rocm-smi",
					})
				}
			}
		}
	}

	if len(gpus) == 0 {
		return []GPUStatus{{
			Name: "AMD GPU read failed",
			Note: "Verify rocm-smi availability and GPU presence",
		}}
	}

	return gpus
}

func readIntelGPUInfo() ([]GPUStatus, error) {
	// Read from /sys/class/drm for Intel integrated GPUs
	drmPaths, err := filepath.Glob("/sys/class/drm/card*")
	if err != nil {
		return nil, err
	}

	for _, drmPath := range drmPaths {
		// Skip render nodes
		if strings.Contains(drmPath, "renderD") {
			continue
		}

		devicePath := filepath.Join(drmPath, "device")
		if deviceInfo, err := os.ReadFile(filepath.Join(devicePath, "vendor")); err == nil {
			// Intel vendor ID is 0x8086
			if strings.Contains(string(deviceInfo), "0x8086") {
				// Try to read GPU name
				var name string
				if modelName, err := os.ReadFile(filepath.Join(devicePath, "model")); err == nil {
					name = strings.TrimSpace(string(modelName))
				} else {
					name = "Intel Integrated GPU"
				}

				return []GPUStatus{{
					Name:  name,
					Usage: -1, // Usage requires additional tools
					Note:  "Intel integrated graphics",
				}}, nil
			}
		}
	}

	return nil, errors.New("no Intel GPU found")
}

func readMacGPUInfo() ([]GPUStatus, error) {
	ctx, cancel := context.WithTimeout(context.Background(), systemProfilerTimeout)
	defer cancel()

	if !commandExists("system_profiler") {
		return nil, errors.New("system_profiler unavailable")
	}

	out, err := runCmd(ctx, "system_profiler", "-json", "SPDisplaysDataType")
	if err != nil {
		return nil, err
	}

	var data struct {
		Displays []struct {
			Name   string `json:"_name"`
			VRAM   string `json:"spdisplays_vram"`
			Vendor string `json:"spdisplays_vendor"`
			Metal  string `json:"spdisplays_metal"`
			Cores  string `json:"sppci_cores"`
		} `json:"SPDisplaysDataType"`
	}
	if err := json.Unmarshal([]byte(out), &data); err != nil {
		return nil, err
	}

	var gpus []GPUStatus
	for _, d := range data.Displays {
		if d.Name == "" {
			continue
		}
		noteParts := []string{}
		if d.VRAM != "" {
			noteParts = append(noteParts, "VRAM "+d.VRAM)
		}
		if d.Metal != "" {
			noteParts = append(noteParts, d.Metal)
		}
		if d.Vendor != "" {
			noteParts = append(noteParts, d.Vendor)
		}
		note := strings.Join(noteParts, " · ")
		coreCount, _ := strconv.Atoi(d.Cores)
		gpus = append(gpus, GPUStatus{
			Name:      d.Name,
			Usage:     -1, // Will be updated with real-time data
			CoreCount: coreCount,
			Note:      note,
		})
	}

	if len(gpus) == 0 {
		return []GPUStatus{{
			Name: "GPU info unavailable",
			Note: "Unable to parse system_profiler output",
		}}, nil
	}

	return gpus, nil
}

// getMacGPUUsage gets GPU active residency from powermetrics.
// Returns -1 if unavailable (e.g., not running as root).
func getMacGPUUsage() float64 {
	ctx, cancel := context.WithTimeout(context.Background(), powermetricsTimeout)
	defer cancel()

	// powermetrics requires root, but we try anyway - some systems may have it enabled
	out, err := runCmd(ctx, "powermetrics", "--samplers", "gpu_power", "-i", "500", "-n", "1")
	if err != nil {
		return -1
	}

	// Parse "GPU HW active residency:   X.XX%"
	matches := gpuActiveResidencyRe.FindStringSubmatch(out)
	if len(matches) >= 2 {
		usage, err := strconv.ParseFloat(matches[1], 64)
		if err == nil {
			return usage
		}
	}

	// Fallback: parse "GPU idle residency: X.XX%" and calculate active
	matchesIdle := gpuIdleResidencyRe.FindStringSubmatch(out)
	if len(matchesIdle) >= 2 {
		idle, err := strconv.ParseFloat(matchesIdle[1], 64)
		if err == nil {
			return 100.0 - idle
		}
	}

	return -1
}
