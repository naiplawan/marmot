package main

import (
	"path/filepath"
	"strings"
)

// isCleanableDir checks if a directory is safe to manually delete
// but NOT cleaned by marmot clean (so user might want to delete it manually)
func isCleanableDir(path string) bool {
	if path == "" {
		return false
	}

	// Exclude paths that marmot clean will handle automatically
	// These are system caches/logs that marmot clean already processes
	if isHandledByMarmotClean(path) {
		return false
	}

	baseName := filepath.Base(path)

	// Only mark project dependencies and build outputs
	// These are safe to delete but mo clean won't touch them
	if projectDependencyDirs[baseName] {
		return true
	}

	return false
}

// isHandledByMarmotClean checks if this path will be cleaned by marmot clean
func isHandledByMarmotClean(path string) bool {
	// Paths that marmot clean handles (from clean.sh)
	cleanPaths := []string{
		// macOS paths
		"/Library/Caches/",
		"/Library/Logs/",
		"/Library/Saved Application State/",
		"/.Trash/",
		"/Library/DiagnosticReports/",

		// Linux paths
		"/.cache/",
		"/.local/share/Trash/",
		"/.local/share/logs/",
		"/.local/state/",
		"/var/cache/",
		"/var/log/",
		"/var/crash/",
		"/var/lib/apport/coredump/",
		"/var/lib/systemd/coredump/",
	}

	for _, p := range cleanPaths {
		if strings.Contains(path, p) {
			return true
		}
	}

	return false
}

// Project dependency and build directories
// These are safe to delete manually but marmot clean won't touch them
var projectDependencyDirs = map[string]bool{
	// JavaScript/Node dependencies
	"node_modules":     true,
	"bower_components": true,
	".yarn":            true, // Yarn local cache
	".pnpm-store":      true, // pnpm store

	// Python dependencies and outputs
	"venv":               true,
	".venv":              true,
	"virtualenv":         true,
	"__pycache__":        true,
	".pytest_cache":      true,
	".mypy_cache":        true,
	".ruff_cache":        true,
	".tox":               true,
	".eggs":              true,
	"htmlcov":            true, // Coverage reports
	".ipynb_checkpoints": true, // Jupyter checkpoints

	// Ruby dependencies
	"vendor":  true,
	".bundle": true,

	// Java/Kotlin/Scala
	".gradle": true, // Project-level Gradle cache
	"out":     true, // IntelliJ IDEA build output

	// Build outputs (can be rebuilt)
	"build":         true,
	"dist":          true,
	"target":        true,
	".next":         true,
	".nuxt":         true,
	".output":       true,
	".parcel-cache": true,
	".turbo":        true,
	".vite":         true, // Vite cache
	".nx":           true, // Nx cache
	"coverage":      true,
	".coverage":     true,
	".nyc_output":   true, // NYC coverage

	// Frontend framework outputs
	".angular":    true, // Angular CLI cache
	".svelte-kit": true, // SvelteKit build
	".astro":      true, // Astro cache
	".docusaurus": true, // Docusaurus build

	// iOS/macOS development
	"DerivedData": true,
	"Pods":        true,
	".build":      true,
	"Carthage":    true,

	// Other tools
	".terraform": true, // Terraform plugins

	// Linux-specific development directories
	".cargo":     true, // Rust Cargo cache
	".maven":     true, // Maven repository
	".npm":       true, // npm cache (global)
}
