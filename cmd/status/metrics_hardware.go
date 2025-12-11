package main

import (
	"bufio"
	"context"
	"os"
	"runtime"
	"strings"
	"time"
)

func collectHardware(totalRAM uint64, disks []DiskStatus) HardwareInfo {
	if runtime.GOOS == "darwin" {
		// Get model and CPU from system_profiler
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		var model, cpuModel, osVersion string

		// Get hardware overview
		out, err := runCmd(ctx, "system_profiler", "SPHardwareDataType")
		if err == nil {
			lines := strings.Split(out, "\n")
			for _, line := range lines {
				lower := strings.ToLower(strings.TrimSpace(line))
				// Prefer "Model Name" over "Model Identifier"
				if strings.Contains(lower, "model name:") {
					parts := strings.Split(line, ":")
					if len(parts) == 2 {
						model = strings.TrimSpace(parts[1])
					}
				}
				if strings.Contains(lower, "chip:") {
					parts := strings.Split(line, ":")
					if len(parts) == 2 {
						cpuModel = strings.TrimSpace(parts[1])
					}
				}
				if strings.Contains(lower, "processor name:") && cpuModel == "" {
					parts := strings.Split(line, ":")
					if len(parts) == 2 {
						cpuModel = strings.TrimSpace(parts[1])
					}
				}
			}
		}

		// Get macOS version
		ctx2, cancel2 := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel2()
		out2, err := runCmd(ctx2, "sw_vers", "-productVersion")
		if err == nil {
			osVersion = "macOS " + strings.TrimSpace(out2)
		}

		// Get disk size
		diskSize := "Unknown"
		if len(disks) > 0 {
			diskSize = humanBytes(disks[0].Total)
		}

		return HardwareInfo{
			Model:     model,
			CPUModel:  cpuModel,
			TotalRAM:  humanBytes(totalRAM),
			DiskSize:  diskSize,
			OSVersion: osVersion,
		}
	}

	// Linux hardware detection
	return collectLinuxHardware(totalRAM, disks)
}

func collectLinuxHardware(totalRAM uint64, disks []DiskStatus) HardwareInfo {
	var model, cpuModel, osVersion string

	// Get system model from DMI or fallback
	model = getLinuxSystemModel()

	// Get CPU model
	cpuModel = getLinuxCPUModel()

	// Get OS version
	osVersion = getLinuxOSVersion()

	// Get disk size
	diskSize := "Unknown"
	if len(disks) > 0 {
		diskSize = humanBytes(disks[0].Total)
	}

	return HardwareInfo{
		Model:     model,
		CPUModel:  cpuModel,
		TotalRAM:  humanBytes(totalRAM),
		DiskSize:  diskSize,
		OSVersion: osVersion,
	}
}

func getLinuxSystemModel() string {
	// Try to get model from DMI
	if modelBytes, err := os.ReadFile("/sys/class/dmi/id/product_name"); err == nil {
		model := strings.TrimSpace(string(modelBytes))
		if manufacturerBytes, err := os.ReadFile("/sys/class/dmi/id/sys_vendor"); err == nil {
			manufacturer := strings.TrimSpace(string(manufacturerBytes))
			return manufacturer + " " + model
		}
		return model
	}

	// Fallback for virtual machines
	if productBytes, err := os.ReadFile("/sys/class/dmi/id/product_name"); err == nil {
		productStr := strings.TrimSpace(string(productBytes))
		if strings.Contains(strings.ToLower(productStr), "vmware") ||
			strings.Contains(strings.ToLower(productStr), "virtualbox") ||
			strings.Contains(strings.ToLower(productStr), "kvm") ||
			strings.Contains(strings.ToLower(productStr), "qemu") {
			return "Virtual Machine"
		}
		return productStr
	}

	// Generic fallback
	return "Unknown Linux System"
}

func getLinuxCPUModel() string {
	// Try to read from /proc/cpuinfo
	if file, err := os.Open("/proc/cpuinfo"); err == nil {
		defer file.Close()
		scanner := bufio.NewScanner(file)
		for scanner.Scan() {
			line := scanner.Text()
			if strings.HasPrefix(line, "model name") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					return strings.TrimSpace(parts[1])
				}
			}
		}
	}

	// Fallback to architecture
	return runtime.GOARCH
}

func getLinuxOSVersion() string {
	// Try /etc/os-release first (modern standard)
	if data, err := os.ReadFile("/etc/os-release"); err == nil {
		lines := strings.Split(string(data), "\n")
		var name, version string
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "NAME=") {
				name = strings.Trim(strings.TrimPrefix(line, "NAME="), "\"")
			}
			if strings.HasPrefix(line, "VERSION_ID=") {
				version = strings.Trim(strings.TrimPrefix(line, "VERSION_ID="), "\"")
			}
		}
		if name != "" {
			if version != "" {
				return name + " " + version
			}
			return name
		}
	}

	// Fallback: try lsb_release
	if commandExists("lsb_release") {
		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel()
		if out, err := runCmd(ctx, "lsb_release", "-d"); err == nil {
			parts := strings.SplitN(out, ":", 2)
			if len(parts) == 2 {
				return strings.TrimSpace(parts[1])
			}
		}
	}

	// Generic fallback
	return "Linux"
}
