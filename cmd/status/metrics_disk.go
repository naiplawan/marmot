package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/disk"
)

var skipDiskMounts = map[string]bool{
	// macOS specific
	"/System/Volumes/VM":       true,
	"/System/Volumes/Preboot":  true,
	"/System/Volumes/Update":   true,
	"/System/Volumes/xarts":    true,
	"/System/Volumes/Hardware": true,
	"/System/Volumes/Data":     true,

	// Linux specific
	"/dev":                     true,
	"/proc":                    true,
	"/sys":                     true,
	"/run":                     true,
	"/sys/fs/cgroup":           true,
	"/tmp":                     true,
	"/var/lock":                true,
	"/var/run":                 true,
}

func collectDisks() ([]DiskStatus, error) {
	partitions, err := disk.Partitions(false)
	if err != nil {
		return nil, err
	}

	var (
		disks      []DiskStatus
		seenDevice = make(map[string]bool)
		seenVolume = make(map[string]bool)
	)
	for _, part := range partitions {
		if strings.HasPrefix(part.Device, "/dev/loop") {
			continue
		}
		if skipDiskMounts[part.Mountpoint] {
			continue
		}
		if strings.HasPrefix(part.Mountpoint, "/System/Volumes/") {
			continue
		}
		// Skip private volumes
		if strings.HasPrefix(part.Mountpoint, "/private/") {
			continue
		}
		baseDevice := baseDeviceName(part.Device)
		if baseDevice == "" {
			baseDevice = part.Device
		}
		if seenDevice[baseDevice] {
			continue
		}
		usage, err := disk.Usage(part.Mountpoint)
		if err != nil || usage.Total == 0 {
			continue
		}
		// Skip small volumes (< 1GB)
		if usage.Total < 1<<30 {
			continue
		}
		// For APFS volumes, use a more precise dedup key (bytes level)
		// to handle shared storage pools properly
		volKey := fmt.Sprintf("%s:%d", part.Fstype, usage.Total)
		if seenVolume[volKey] {
			continue
		}
		disks = append(disks, DiskStatus{
			Mount:       part.Mountpoint,
			Device:      part.Device,
			Used:        usage.Used,
			Total:       usage.Total,
			UsedPercent: usage.UsedPercent,
			Fstype:      part.Fstype,
		})
		seenDevice[baseDevice] = true
		seenVolume[volKey] = true
	}

	annotateDiskTypes(disks)

	sort.Slice(disks, func(i, j int) bool {
		return disks[i].Total > disks[j].Total
	})

	if len(disks) > 3 {
		disks = disks[:3]
	}

	return disks, nil
}

func annotateDiskTypes(disks []DiskStatus) {
	if len(disks) == 0 {
		return
	}

	if runtime.GOOS == "darwin" && commandExists("diskutil") {
		// macOS diskutil-based detection
		cache := make(map[string]bool)
		for i := range disks {
			base := baseDeviceName(disks[i].Device)
			if base == "" {
				base = disks[i].Device
			}
			if val, ok := cache[base]; ok {
				disks[i].External = val
				continue
			}
			external, err := isExternalDisk(base)
			if err != nil {
				external = strings.HasPrefix(disks[i].Mount, "/Volumes/")
			}
			disks[i].External = external
			cache[base] = external
		}
		return
	}

	// Linux detection based on mount points and device names
	for i := range disks {
		// Check if it's mounted under /media or /mnt (typical external mount points)
		if strings.HasPrefix(disks[i].Mount, "/media/") || strings.HasPrefix(disks[i].Mount, "/mnt/") {
			disks[i].External = true
			continue
		}

		// Check device name patterns (USB/SD card typically have specific patterns)
		device := disks[i].Device
		if strings.Contains(device, "usb") ||
			strings.Contains(device, "sd") && !strings.HasPrefix(device, "/dev/sda") ||
			strings.Contains(device, "mmcblk") ||
			strings.Contains(device, "nvme") && !strings.HasPrefix(device, "/dev/nvme0") {
			disks[i].External = true
			continue
		}

		// Check if it's a removable device via sysfs
		if isRemovableLinux(device) {
			disks[i].External = true
		}
	}
}

func baseDeviceName(device string) string {
	device = strings.TrimPrefix(device, "/dev/")
	if !strings.HasPrefix(device, "disk") {
		return device
	}
	for i := 4; i < len(device); i++ {
		if device[i] == 's' {
			return device[:i]
		}
	}
	return device
}

func isExternalDisk(device string) (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	out, err := runCmd(ctx, "diskutil", "info", device)
	if err != nil {
		return false, err
	}
	var (
		found    bool
		external bool
	)
	for _, line := range strings.Split(out, "\n") {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "Internal:") {
			found = true
			external = strings.Contains(trim, "No")
			break
		}
		if strings.HasPrefix(trim, "Device Location:") {
			found = true
			external = strings.Contains(trim, "External")
		}
	}
	if !found {
		return false, errors.New("diskutil info missing Internal field")
	}
	return external, nil
}

func (c *Collector) collectDiskIO(now time.Time) DiskIOStatus {
	counters, err := disk.IOCounters()
	if err != nil || len(counters) == 0 {
		return DiskIOStatus{}
	}

	var total disk.IOCountersStat
	for _, v := range counters {
		total.ReadBytes += v.ReadBytes
		total.WriteBytes += v.WriteBytes
	}

	if c.lastDiskAt.IsZero() {
		c.prevDiskIO = total
		c.lastDiskAt = now
		return DiskIOStatus{}
	}

	elapsed := now.Sub(c.lastDiskAt).Seconds()
	if elapsed <= 0 {
		elapsed = 1
	}

	readRate := float64(total.ReadBytes-c.prevDiskIO.ReadBytes) / 1024 / 1024 / elapsed
	writeRate := float64(total.WriteBytes-c.prevDiskIO.WriteBytes) / 1024 / 1024 / elapsed

	c.prevDiskIO = total
	c.lastDiskAt = now

	if readRate < 0 {
		readRate = 0
	}
	if writeRate < 0 {
		writeRate = 0
	}

	return DiskIOStatus{ReadRate: readRate, WriteRate: writeRate}
}

// isRemovableLinux checks if a device is removable on Linux via sysfs
func isRemovableLinux(device string) bool {
	// Convert device path to sysfs path
	// e.g., /dev/sda1 -> /sys/block/sda/sda1/removable
	device = strings.TrimPrefix(device, "/dev/")

	// Handle different device types
	var sysPath string
	if strings.HasPrefix(device, "sd") {
		// SD devices: get base device (sda1 -> sda)
		for i := len(device); i > 0; i-- {
			if device[i-1] >= '0' && device[i-1] <= '9' {
				continue
			}
			baseDevice := device[:i]
			sysPath = fmt.Sprintf("/sys/block/%s/removable", baseDevice)
			break
		}
	} else if strings.HasPrefix(device, "nvme") {
		// NVMe devices: nvme0n1p1 -> nvme0n1
		parts := strings.Split(device, "p")
		if len(parts) > 0 {
			sysPath = fmt.Sprintf("/sys/block/%s/removable", parts[0])
		}
	} else if strings.HasPrefix(device, "mmcblk") {
		// MMC devices (SD cards)
		for i := len(device); i > 0; i-- {
			if device[i-1] >= '0' && device[i-1] <= '9' {
				continue
			}
			baseDevice := device[:i]
			sysPath = fmt.Sprintf("/sys/block/%s/removable", baseDevice)
			break
		}
	}

	if sysPath == "" {
		return false
	}

	// Read the removable attribute
	if data, err := os.ReadFile(sysPath); err == nil {
		if removable, err := strconv.Atoi(strings.TrimSpace(string(data))); err == nil {
			return removable == 1
		}
	}

	return false
}
